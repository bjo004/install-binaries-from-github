#!/usr/bin/env bash

# Global configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/install_from_github.config"
INSTALL_PATH="/usr/local/bin"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Arrays to track installation results
SUCCESSFUL_INSTALLS=()
FAILED_INSTALLS=()
SKIPPED_INSTALLS=()

# Function to normalize version strings by removing "v" prefix
normalize_version() {
  local version="$1"
  # Remove leading "v" if present
  echo "${version#v}"
}

# Function to print colored output
print_color() {
  local color=$1
  local message=$2
  echo -e "${color}${message}${NC}"
}

# Function to print status messages
print_status() {
  print_color "$BLUE" "ℹ $1"
}

print_success() {
  print_color "$GREEN" "✓ $1"
}

print_warning() {
  print_color "$YELLOW" "⚠ $1"
}

print_error() {
  print_color "$RED" "✗ $1"
}

# Function to check if config file exists
check_config_file() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    print_error "Config file not found: $CONFIG_FILE"
    print_status "Create the config file or use --config to specify a different location"
    exit 1
  fi
  
  if [[ ! -r "$CONFIG_FILE" ]]; then
    print_error "Config file is not readable: $CONFIG_FILE"
    exit 1
  fi
}

# Function to check prerequisites
check_prerequisites() {
  local missing_tools=()
  local required_tools=("curl" "tar" "unzip" "sudo" "grep" "awk" "sed")
  
  for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing_tools+=("$tool")
    fi
  done
  
  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    print_error "Missing required tools:"
    for tool in "${missing_tools[@]}"; do
      echo "  - $tool"
    done
    echo
    print_error "Please install missing tools and try again."
    
    # Create install command with actual missing tools
    local install_tools="${missing_tools[*]}"
    
    # Provide installation suggestions based on common package managers
    if command -v apt >/dev/null 2>&1; then
      print_status "Try: sudo apt update && sudo apt install -y $install_tools"
    elif command -v yum >/dev/null 2>&1; then
      print_status "Try: sudo yum install -y $install_tools"
    elif command -v dnf >/dev/null 2>&1; then
      print_status "Try: sudo dnf install -y $install_tools"
    elif command -v pacman >/dev/null 2>&1; then
      print_status "Try: sudo pacman -S $install_tools"
    elif command -v zypper >/dev/null 2>&1; then
      print_status "Try: sudo zypper install $install_tools"
    fi
    
    exit 1
  fi
}

# Function to get all available tools from config
get_available_tools() {
  grep '^\[.*\]$' "$CONFIG_FILE" | sed 's/\[//g' | sed 's/\]//g'
}

# Function to check if tool exists in config
tool_exists() {
  local tool="$1"
  grep -q "^\[$tool\]$" "$CONFIG_FILE"
}

# Function to get tool description
get_tool_description() {
  local tool="$1"
  awk -v tool="$tool" '
    /^\[/ { current_section = substr($0, 2, length($0)-2) }
    current_section == tool && /^DESCRIPTION=/ { 
      gsub(/^DESCRIPTION="?|"?$/, ""); 
      print; 
      exit 
    }
  ' "$CONFIG_FILE"
}

# Function to load tool configuration
load_tool_config() {
  local tool="$1"
  
  # Reset variables
  unset APPLICATION GITHUB_REPO VERSION_CMD_ARGS VERSION_REGEX ARCHIVE_PATTERN BINARY_NAME DESCRIPTION
  
  # Load configuration for the tool
  eval "$(awk -v tool="$tool" '
    /^\[/ { current_section = substr($0, 2, length($0)-2) }
    current_section == tool && /^[A-Z_]+=/ { print }
  ' "$CONFIG_FILE")"
  
  # Validate required variables
  if [[ -z "$APPLICATION" || -z "$GITHUB_REPO" || -z "$ARCHIVE_PATTERN" || -z "$BINARY_NAME" ]]; then
    print_error "Invalid configuration for tool: $tool"
    print_error "Missing required variables: APPLICATION, GITHUB_REPO, ARCHIVE_PATTERN, or BINARY_NAME"
    return 1
  fi
  
  return 0
}

# Function to get installed application version and path
get_installed_info() {
  local app="$1"
  local version_args="$2"
  local version_regex="$3"
  
  if command -v "$app" >/dev/null 2>&1; then
    # Get path to installed application
    local app_path
    app_path=$(command -v "$app")
    # Get version using specified command and regex
    local app_version
    if [[ -n "$version_args" ]]; then
      app_version=$($app $version_args 2>/dev/null | grep -oP "$version_regex" | head -1)
    else
      app_version=$($app --version 2>/dev/null | grep -oP "$version_regex" | head -1)
    fi
    
    # Normalize version by removing "v" prefix
    if [[ -n "$app_version" ]]; then
      app_version=$(normalize_version "$app_version")
    fi
    
    echo "$app_path:$app_version"
  fi
}

# Function to detect system architecture
get_architecture() {
  local arch
  arch=$(uname -m)
  case $arch in
    x86_64) echo "amd64" ;;
    aarch64) echo "arm64" ;;
    armv7l) echo "arm" ;;
    i386|i686) echo "386" ;;
    *) 
      print_error "Unsupported architecture: $arch"
      return 1
      ;;
  esac
}

# Function to get latest version from GitHub API
get_latest_version() {
  local repo="$1"
  local latest_version
  latest_version=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')
  
  if [[ -z "$latest_version" ]]; then
    print_error "Failed to get latest version for $repo"
    return 1
  fi
  
  # Normalize version by removing "v" prefix
  latest_version=$(normalize_version "$latest_version")
  
  echo "$latest_version"
}

# Function to check and kill running processes
kill_running_processes() {
  local app="$1"
  if pgrep -x "$app" >/dev/null 2>&1; then
    print_warning "Found running $app processes. Terminating..."
    pkill -x "$app"
    # Wait a moment for graceful termination
    sleep 2
    # Force kill if still running
    if pgrep -x "$app" >/dev/null 2>&1; then
      print_warning "Force killing remaining $app processes..."
      pkill -9 -x "$app"
    fi
    print_success "$app processes terminated."
  fi
}

# Function to display help
show_help() {
  cat << 'EOF'
GitHub Binary Installer Script

USAGE:
  install_from_github.sh [OPTIONS] [TOOLS...]
  install_from_github.sh TOOL1 [TOOL2 ...]        # Install/upgrade tools (default action)

OPTIONS:
  -h, --help              Show this help message
  -l, --list              List all available tools in config
  -s, --show-installed    Show installed vs latest versions for all tools
  -i, --install TOOL(S)   Install specific tool(s) (explicit)
  -u, --uninstall TOOL(S) Uninstall specific tool(s)
  -a, --install-all       Install all tools from config
      --upgrade-installed Upgrade only installed tools that are outdated
      --uninstall-all     Uninstall all tools from config
  -c, --config FILE       Use custom config file (default: ./install_from_github.config)
  -p, --path PATH         Install to custom path (default: /usr/local/bin)
  -f, --force             Force reinstall even if same version (only affects installed tools)
  -d, --dry-run           Show what would be installed without installing
  -y, --yes               Skip confirmation prompts
  -v, --verbose           Show detailed output

EXAMPLES:
  install_from_github.sh jq yq kubectl           # Install/upgrade these tools
  install_from_github.sh jq yq --force           # Force reinstall if already installed
  install_from_github.sh --list                  # List available tools
  install_from_github.sh --show-installed        # Show version status
  install_from_github.sh --upgrade-installed     # Upgrade outdated installed tools
  install_from_github.sh --upgrade-installed --yes # Upgrade without confirmation
  install_from_github.sh --install-all           # Install all tools
  install_from_github.sh --uninstall jq yq       # Remove specific tools
  install_from_github.sh --uninstall-all         # Remove all tools
  install_from_github.sh --install-all --dry-run # Preview what would be installed

CONFIG FILE:
  Default location: ./install_from_github.config
  Uses INI-style format with [tool_name] sections

ADDING NEW TOOLS TO CONFIG:
  To add a new tool, follow these steps:

  1. IDENTIFY THE TOOL:
     - Find the GitHub repository (e.g., "user/repo")
     - Verify it has releases at: https://github.com/user/repo/releases

  2. DETERMINE VERSION COMMAND & REGEX:
     - Install the tool manually or check documentation
     - Run: tool_name --version (or -v, version, etc.)
     - Example outputs and their regex patterns:
       "tool 1.2.3"           → VERSION_REGEX='\d+\.\d+\.\d+'
       "tool v1.2.3"          → VERSION_REGEX='v\d+\.\d+\.\d+'
       "tool-1.2.3"           → VERSION_REGEX='tool-\d+\.\d+\.\d+'
       "Version: 1.2.3 ..."   → VERSION_REGEX='\d+\.\d+\.\d+'

  3. FIND ARCHIVE PATTERN:
     - Visit: https://github.com/user/repo/releases/latest
     - Look for Linux AMD64 downloads (avoid .deb/.rpm)
     - Note the filename pattern, examples:
       "tool_1.2.3_linux_amd64.tar.gz"     → "tool_%VERSION%_linux_amd64.tar.gz"
       "tool-v1.2.3-linux-amd64.tar.gz"    → "tool-v%VERSION%-linux-amd64.tar.gz"  
       "tool-linux-amd64"                  → "tool-linux-amd64" (single binary)
     - Replace version numbers with %VERSION%
     - Replace architecture with %ARCH% if present

  4. DETERMINE BINARY NAME:
     - For archives: Path to binary inside the extracted archive
       Examples:
       - "tool" (binary at root of archive)
       - "bin/tool" (binary in bin/ subdirectory)
       - "tool-v1.2.3-linux-amd64/tool" (binary in versioned directory)
     - For single binaries: Same as the downloaded filename
     - Use %VERSION% placeholder if needed in path

  5. CREATE CONFIG ENTRY:
     [tool_name]
     DESCRIPTION="Brief description of the tool"
     APPLICATION="tool_name"                    # Binary name for PATH lookup
     GITHUB_REPO="user/repo"                    # GitHub repository
     VERSION_CMD_ARGS="--version"               # Command args to get version
     VERSION_REGEX='\d+\.\d+\.\d+'              # Regex to extract version number
     ARCHIVE_PATTERN="tool_%VERSION%_linux_amd64.tar.gz"  # Download filename pattern
     BINARY_NAME="tool"                         # Path to binary in archive

  6. TEST THE CONFIGURATION:
     - Add the entry to your config file
     - Run: ./install_from_github.sh --list (verify tool appears)
     - Run: ./install_from_github.sh tool_name --dry-run (test download URL)
     - Run: ./install_from_github.sh tool_name -y (actual install)

  COMMON PATTERNS:
  - Single binary: ARCHIVE_PATTERN="tool-linux-amd64", BINARY_NAME="tool-linux-amd64"
  - Tar.gz archive: ARCHIVE_PATTERN="tool_%VERSION%_linux_amd64.tar.gz", BINARY_NAME="tool"
  - Versioned directory: BINARY_NAME="tool-v%VERSION%-linux-amd64/tool"

  TROUBLESHOOTING:
  - "Failed to get latest version": Check GITHUB_REPO is correct
  - "Download/extract failed": Verify ARCHIVE_PATTERN matches actual filename
  - "Binary not found": Check BINARY_NAME path is correct for the archive structure
  - "Tool not detected": Ensure VERSION_REGEX matches the tool's output format

  NOTE: 
  - Only tools distributed via GitHub releases are supported. 
  - Tools that use other distribution methods (like HashiCorp's releases.hashicorp.com) won't work.
  - At the moment there are no checksum verfications
  - If you do not have a GitHub Token, you may reach an API cap which will result in an API error.
EOF
}

# Function to list all available tools
list_tools() {
  local tools
  tools=$(get_available_tools)
  
  if [[ -z "$tools" ]]; then
    print_warning "No tools found in config file"
    return 1
  fi
  
  local tool_count
  tool_count=$(echo "$tools" | wc -l)
  
  print_status "Available tools in $CONFIG_FILE ($tool_count total):"
  echo
  
  printf "%-15s %s\n" "TOOL" "DESCRIPTION"
  printf "%-15s %s\n" "----" "-----------"
  
  while IFS= read -r tool; do
    local description
    description=$(get_tool_description "$tool")
    printf "%-15s %s\n" "$tool" "${description:-No description available}"
  done <<< "$tools"
}

# Function to show installed vs latest versions
show_installed() {
  local tools
  tools=$(get_available_tools)
  
  if [[ -z "$tools" ]]; then
    print_warning "No tools found in config file"
    return 1
  fi
  
  local tool_count
  tool_count=$(echo "$tools" | wc -l)
  
  print_status "Checking installed tools from config ($tool_count total):"
  echo
  
  printf "%-15s %-15s %-15s %s\n" "TOOL" "INSTALLED" "LATEST" "STATUS"
  printf "%-15s %-15s %-15s %s\n" "----" "---------" "------" "------"
  
  while IFS= read -r tool; do
    # Load tool configuration
    if ! load_tool_config "$tool"; then
      printf "%-15s %-15s %-15s %s\n" "$tool" "Error" "Error" "Invalid config"
      continue
    fi
    
    # Get installed version (already normalized)
    local installed_info
    installed_info=$(get_installed_info "$APPLICATION" "$VERSION_CMD_ARGS" "$VERSION_REGEX")
    local installed_version="${installed_info##*:}"
    
    # Get latest version (already normalized)
    local latest_version
    if ! latest_version=$(get_latest_version "$GITHUB_REPO" 2>/dev/null); then
      printf "%-15s %-15s %-15s %s\n" "$tool" "${installed_version:-Not installed}" "Error" "GitHub API error"
      continue
    fi
    
    # Determine status
    local status
    if [[ -z "$installed_version" ]]; then
      status="Available"
      installed_version="Not installed"
    elif [[ "$installed_version" == "$latest_version" ]]; then
      status=$(print_color "$GREEN" "Up to date")
    else
      status=$(print_color "$YELLOW" "Outdated")
    fi
    
    printf "%-15s %-15s %-15s %s\n" "$tool" "$installed_version" "$latest_version" "$status"
  done <<< "$tools"
}

# Function to upgrade installed tools
upgrade_installed() {
  local dry_run="$1"
  
  local tools
  tools=$(get_available_tools)
  
  if [[ -z "$tools" ]]; then
    print_warning "No tools found in config file"
    return 1
  fi
  
  print_status "Checking for outdated installed tools..."
  
  # Find outdated installed tools
  local outdated_tools=()
  while IFS= read -r tool; do
    # Load tool configuration
    if ! load_tool_config "$tool"; then
      continue
    fi
    
    # Get installed version (already normalized)
    local installed_info
    installed_info=$(get_installed_info "$APPLICATION" "$VERSION_CMD_ARGS" "$VERSION_REGEX")
    local installed_version="${installed_info##*:}"
    
    # Skip if not installed
    if [[ -z "$installed_version" ]]; then
      continue
    fi
    
    # Get latest version (already normalized)
    local latest_version
    if ! latest_version=$(get_latest_version "$GITHUB_REPO" 2>/dev/null); then
      [[ "$VERBOSE" == "true" ]] && print_warning "Failed to check latest version for $tool"
      continue
    fi
    
    # Check if outdated
    if [[ "$installed_version" != "$latest_version" ]]; then
      outdated_tools+=("$tool")
      [[ "$VERBOSE" == "true" ]] && echo "  Found outdated: $tool ($installed_version → $latest_version)"
    fi
  done <<< "$tools"
  
  if [[ ${#outdated_tools[@]} -eq 0 ]]; then
    print_success "All installed tools are up to date!"
    return 0
  fi
  
  if [[ "$dry_run" == "true" ]]; then
    print_status "Would upgrade ${#outdated_tools[@]} outdated tool(s):"
    for tool in "${outdated_tools[@]}"; do
      # Load config to get versions
      load_tool_config "$tool"
      local installed_info
      installed_info=$(get_installed_info "$APPLICATION" "$VERSION_CMD_ARGS" "$VERSION_REGEX")
      local installed_version="${installed_info##*:}"
      local latest_version
      latest_version=$(get_latest_version "$GITHUB_REPO" 2>/dev/null)
      echo "  - $tool: $installed_version → $latest_version"
    done
    return 0
  fi
  
  print_status "Found ${#outdated_tools[@]} outdated tool(s) to upgrade"
  
  # Install outdated tools
  local total=${#outdated_tools[@]}
  for i in "${!outdated_tools[@]}"; do
    install_tool "${outdated_tools[$i]}" "$((i+1))" "$total" "$dry_run" "false"
  done
  
  print_summary
}

# Function to install a single tool
install_tool() {
  local tool="$1"
  local current="$2"
  local total="$3"
  local dry_run="$4"
  local force="$5"
  
  print_status "[$current/$total] Processing: $tool"
  
  # Load tool configuration
  if ! load_tool_config "$tool"; then
    FAILED_INSTALLS+=("$tool: Invalid configuration")
    return 1
  fi
  
  # Get installed application info
  local installed_info
  installed_info=$(get_installed_info "$APPLICATION" "$VERSION_CMD_ARGS" "$VERSION_REGEX")
  local installed_path="${installed_info%%:*}"
  local installed_version="${installed_info##*:}"
  
  # Handle --force flag
  if [[ "$force" == "true" ]]; then
    if [[ -z "$installed_path" ]]; then
      print_status "Skipping $tool (not currently installed, use without --force to install)"
      SKIPPED_INSTALLS+=("$tool: Not installed (--force only affects installed tools)")
      return 0
    fi
    # Skip version check when forcing
    [[ "$VERBOSE" == "true" ]] && echo "  Force reinstalling $tool (currently $installed_version)"
  else
    # Get latest version for normal install (already normalized)
    local latest_version
    if ! latest_version=$(get_latest_version "$GITHUB_REPO"); then
      FAILED_INSTALLS+=("$tool: Failed to get latest version")
      return 1
    fi
    
    [[ "$VERBOSE" == "true" ]] && echo "  Latest version: $latest_version"
    [[ "$VERBOSE" == "true" ]] && [[ -n "$installed_version" ]] && echo "  Installed version: $installed_version"
    
    # Check if already up to date (unless forcing)
    if [[ "$installed_version" == "$latest_version" && -n "$installed_path" ]]; then
      print_success "$tool is already up to date ($latest_version)"
      SKIPPED_INSTALLS+=("$tool: Already up to date")
      return 0
    fi
  fi
  
  # Check and kill running processes
  kill_running_processes "$APPLICATION"
  
  if [[ "$dry_run" == "true" ]]; then
    if [[ "$force" == "true" ]]; then
      print_status "Would force reinstall $tool (currently $installed_version)"
    elif [[ -n "$installed_version" ]]; then
      print_status "Would update $tool from $installed_version to $latest_version"
    else
      print_status "Would install $tool $latest_version"
    fi
    return 0
  fi
  
  # Get latest version if not already fetched (for force installs)
  if [[ -z "$latest_version" ]]; then
    if ! latest_version=$(get_latest_version "$GITHUB_REPO"); then
      FAILED_INSTALLS+=("$tool: Failed to get latest version")
      return 1
    fi
  fi
  
  # Get system architecture
  local arch
  if ! arch=$(get_architecture); then
    FAILED_INSTALLS+=("$tool: Unsupported architecture")
    return 1
  fi
  
  # Remove old installation if path differs
  if [[ -n "$installed_path" && "$installed_path" != "$INSTALL_PATH/$APPLICATION" ]]; then
    print_status "Removing old $APPLICATION installation at $installed_path"
    sudo rm -f "$installed_path"
  fi
  
  # Replace %ARCH% and %VERSION% placeholders in patterns
  # Note: Use the original version with "v" prefix for download URLs if needed
  local github_version="v$latest_version"
  local archive_pattern="${ARCHIVE_PATTERN//%ARCH%/$arch}"
  archive_pattern="${archive_pattern//%VERSION%/${latest_version}}"

  local binary_name="${BINARY_NAME//%ARCH%/$arch}"
  binary_name="${binary_name//%VERSION%/${github_version}}"
  
  # Create temporary directory
  local tmp_dir
  tmp_dir=$(mktemp -d)
  
  # Download and install
  local download_url="https://github.com/$GITHUB_REPO/releases/download/v${latest_version}/${archive_pattern}"
  echo "  Download URL: $download_url"
  
  if [[ "$force" == "true" ]]; then
    print_status "Force reinstalling $APPLICATION $latest_version..."
  else
    print_status "Downloading $APPLICATION $latest_version..."
  fi
  
  if [[ "$archive_pattern" == *.tar.gz ]] || [[ "$archive_pattern" == *.tgz ]]; then
    if ! curl -# -L "$download_url" -o "$tmp_dir/archive.tar.gz" || ! tar -xzf "$tmp_dir/archive.tar.gz" -C "$tmp_dir"; then
      print_error "Failed to download or extract $APPLICATION"
      rm -rf "$tmp_dir"
      FAILED_INSTALLS+=("$tool: Download/extract failed")
      return 1
    fi
  elif [[ "$archive_pattern" == *.zip ]]; then
    if ! curl -# -L "$download_url" -o "$tmp_dir/archive.zip" || ! (cd "$tmp_dir" && unzip -q archive.zip); then
      print_error "Failed to download or extract $APPLICATION"
      rm -rf "$tmp_dir"
      FAILED_INSTALLS+=("$tool: Download/extract failed")
      return 1
    fi
  else
    # Single binary file
    if ! curl -# -L "$download_url" -o "$tmp_dir/$APPLICATION"; then
      print_error "Failed to download $APPLICATION"
      rm -rf "$tmp_dir"
      FAILED_INSTALLS+=("$tool: Download failed")
      return 1
    fi
    binary_name="$APPLICATION"
  fi
  
  # Install binary
  print_status "Installing $APPLICATION to $INSTALL_PATH"
  
  # Handle glob patterns in binary_name
  if [[ "$binary_name" == *"*"* ]]; then
    local binary_path
    binary_path=$(find "$tmp_dir" -name "$binary_name" -type f | head -1)
    if [[ -z "$binary_path" ]]; then
      print_error "Binary not found in archive: $binary_name"
      rm -rf "$tmp_dir"
      FAILED_INSTALLS+=("$tool: Binary not found in archive")
      return 1
    fi
  else
    local binary_path="$tmp_dir/$binary_name"
  fi
  
  if [[ ! -f "$binary_path" ]]; then
    print_error "Binary not found: $binary_path"
    rm -rf "$tmp_dir"
    FAILED_INSTALLS+=("$tool: Binary not found")
    return 1
  fi
  
  if ! sudo mv "$binary_path" "$INSTALL_PATH/$APPLICATION"; then
    print_error "Failed to install $APPLICATION"
    rm -rf "$tmp_dir"
    FAILED_INSTALLS+=("$tool: Installation failed")
    return 1
  fi
  
  sudo chmod +x "$INSTALL_PATH/$APPLICATION"
  
  # Cleanup
  rm -rf "$tmp_dir"
  
  if [[ "$force" == "true" ]]; then
    print_success "$APPLICATION $latest_version force reinstalled successfully"
    SUCCESSFUL_INSTALLS+=("$tool: $latest_version (force reinstalled)")
  else
    print_success "$APPLICATION $latest_version installed successfully"
    SUCCESSFUL_INSTALLS+=("$tool: $latest_version")
  fi
  return 0
}

# Function to uninstall tools
uninstall_tools() {
  local tools=("$@")
  local dry_run="$1"
  
  if [[ "$dry_run" == "true" ]]; then
    tools=("${@:2}")
  fi
  
  print_status "Uninstalling tools from config..."
  
  local removed_count=0
  local skipped_count=0
  
  for tool in "${tools[@]}"; do
    # Load tool configuration
    if ! load_tool_config "$tool"; then
      print_error "Invalid configuration for tool: $tool"
      continue
    fi
    
    # Check if tool is installed
    local installed_info
    installed_info=$(get_installed_info "$APPLICATION" "$VERSION_CMD_ARGS" "$VERSION_REGEX")
    local installed_path="${installed_info%%:*}"
    
    if [[ -z "$installed_path" ]]; then
      [[ "$VERBOSE" == "true" ]] && print_status "Skipping $tool (not installed)"
      ((skipped_count++))
      continue
    fi
    
    if [[ "$dry_run" == "true" ]]; then
      print_status "Would remove: $tool ($installed_path)"
      continue
    fi
    
    # Kill running processes
    kill_running_processes "$APPLICATION"
    
    # Remove binary
    if sudo rm -f "$installed_path"; then
      print_success "Removed $tool from $installed_path"
      ((removed_count++))
    else
      print_error "Failed to remove $tool from $installed_path"
    fi
  done
  
  if [[ "$dry_run" != "true" ]]; then
    echo
    print_status "Uninstall complete: $removed_count removed, $skipped_count skipped"
  fi
}

# Function to uninstall all tools
uninstall_all_tools() {
  local dry_run="$1"
  
  # Get all available tools
  local tools
  mapfile -t tools < <(get_available_tools)
  
  if [[ ${#tools[@]} -eq 0 ]]; then
    print_warning "No tools found in config file"
    return 1
  fi
  
  # Filter to only installed tools
  local installed_tools=()
  for tool in "${tools[@]}"; do
    if load_tool_config "$tool"; then
      local installed_info
      installed_info=$(get_installed_info "$APPLICATION" "$VERSION_CMD_ARGS" "$VERSION_REGEX")
      local installed_path="${installed_info%%:*}"
      if [[ -n "$installed_path" ]]; then
        installed_tools+=("$tool")
      fi
    fi
  done
  
  if [[ ${#installed_tools[@]} -eq 0 ]]; then
    print_status "No tools from config are currently installed"
    return 0
  fi
  
  if [[ "$dry_run" == "true" ]]; then
    uninstall_tools true "${installed_tools[@]}"
  else
    uninstall_tools "${installed_tools[@]}"
  fi
}

# Function to print installation summary
print_summary() {
  echo
  print_status "Installation Summary:"
  
  if [[ ${#SUCCESSFUL_INSTALLS[@]} -gt 0 ]]; then
    echo
    print_success "Successfully installed (${#SUCCESSFUL_INSTALLS[@]}):"
    for install in "${SUCCESSFUL_INSTALLS[@]}"; do
      echo "  ✓ $install"
    done
  fi
  
  if [[ ${#SKIPPED_INSTALLS[@]} -gt 0 ]]; then
    echo
    print_warning "Skipped (${#SKIPPED_INSTALLS[@]}):"
    for skip in "${SKIPPED_INSTALLS[@]}"; do
      echo "  - $skip"
    done
  fi
  
  if [[ ${#FAILED_INSTALLS[@]} -gt 0 ]]; then
    echo
    print_error "Failed (${#FAILED_INSTALLS[@]}):"
    for failure in "${FAILED_INSTALLS[@]}"; do
      echo "  ✗ $failure"
    done
    echo
    print_error "Some installations failed. Check the errors above."
    return 1
  fi
  
  return 0
}

# Function to validate tools exist in config
validate_tools() {
  local tools=("$@")
  local invalid_tools=()
  
  for tool in "${tools[@]}"; do
    if ! tool_exists "$tool"; then
      invalid_tools+=("$tool")
    fi
  done
  
  if [[ ${#invalid_tools[@]} -gt 0 ]]; then
    print_error "The following tools are not available in the config:"
    for tool in "${invalid_tools[@]}"; do
      echo "  - $tool"
    done
    echo
    print_status "Run '$0 --list' to see available tools"
    return 1
  fi
  
  return 0
}

# Function to confirm installation
confirm_installation() {
  local action="$1"
  shift
  local tools=("$@")
  local count=${#tools[@]}
  
  echo
  if [[ "$action" == "uninstall" ]]; then
    if [[ $count -eq 1 ]]; then
      print_status "About to uninstall: ${tools[0]}"
    else
      print_status "About to uninstall $count tools:"
      for tool in "${tools[@]}"; do
        echo "  - $tool"
      done
    fi
  elif [[ "$action" == "upgrade" ]]; then
    if [[ $count -eq 1 ]]; then
      print_status "About to upgrade: ${tools[0]}"
    else
      print_status "About to upgrade $count outdated tools:"
      for tool in "${tools[@]}"; do
        # Show current vs latest version
        if load_tool_config "$tool"; then
          local installed_info
          installed_info=$(get_installed_info "$APPLICATION" "$VERSION_CMD_ARGS" "$VERSION_REGEX")
          local installed_version="${installed_info##*:}"
          local latest_version
          if latest_version=$(get_latest_version "$GITHUB_REPO" 2>/dev/null); then
            echo "  - $tool: $installed_version → $latest_version"
          else
            echo "  - $tool"
          fi
        else
          echo "  - $tool"
        fi
      done
    fi
  else
    if [[ $count -eq 1 ]]; then
      print_status "About to install: ${tools[0]}"
    else
      print_status "About to install $count tools:"
      for tool in "${tools[@]}"; do
        echo "  - $tool"
      done
    fi
  fi
  
  echo
  read -p "Continue? (y/N): " -n 1 -r
  echo
  
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Operation cancelled"
    return 1
  fi
  
  return 0
}

# Main execution
main() {
  local action=""
  local tools=()
  local dry_run=false
  local skip_confirm=false
  local force=false
  
  # If no arguments provided, show help
  if [[ $# -eq 0 ]]; then
    show_help
    exit 0
  fi
  
  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      -l|--list)
        action="list"
        shift
        ;;
      -s|--show-installed)
        action="show-installed"
        shift
        ;;
      -i|--install)
        action="install"
        shift
        # Collect all following arguments as tools until we hit another option
        while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
          tools+=("$1")
          shift
        done
        ;;
      -u|--uninstall)
        action="uninstall"
        shift
        # Collect all following arguments as tools until we hit another option
        while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
          tools+=("$1")
          shift
        done
        ;;
      -a|--install-all)
        action="install-all"
        shift
        ;;
      --upgrade-installed)
        action="upgrade-installed"
        shift
        ;;
      --uninstall-all)
        action="uninstall-all"
        shift
        ;;
      -c|--config)
        CONFIG_FILE="$2"
        shift 2
        ;;
      -p|--path)
        INSTALL_PATH="$2"
        shift 2
        ;;
      -f|--force)
        force=true
        shift
        ;;
      -d|--dry-run)
        dry_run=true
        shift
        ;;
      -y|--yes)
        skip_confirm=true
        shift
        ;;
      -v|--verbose)
        VERBOSE=true
        shift
        ;;
      -*)
        print_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
      *)
        # Default action: install tools (when arguments don't start with -)
        if [[ -z "$action" ]]; then
          action="install"
        fi
        tools+=("$1")
        shift
        ;;
    esac
  done
  
  # Check prerequisites first
  check_prerequisites
  
  # Check if config file exists
  check_config_file
  
  # Execute based on action
  case "$action" in
    "list")
      list_tools
      ;;
    "show-installed")
      show_installed
      ;;
    "upgrade-installed")
      # Confirm upgrade unless dry run or skip confirm
      if [[ "$dry_run" != "true" && "$skip_confirm" != "true" ]]; then
        # Get outdated tools for confirmation
        local outdated_tools=()
        mapfile -t all_tools < <(get_available_tools)
        for tool in "${all_tools[@]}"; do
          if load_tool_config "$tool"; then
            local installed_info
            installed_info=$(get_installed_info "$APPLICATION" "$VERSION_CMD_ARGS" "$VERSION_REGEX")
            local installed_version="${installed_info##*:}"
            
            # Skip if not installed
            if [[ -z "$installed_version" ]]; then
              continue
            fi
            
            # Get latest version
            local latest_version
            if latest_version=$(get_latest_version "$GITHUB_REPO" 2>/dev/null); then
              # Check if outdated
              if [[ "$installed_version" != "$latest_version" ]]; then
                outdated_tools+=("$tool")
              fi
            fi
          fi
        done
        
        if [[ ${#outdated_tools[@]} -eq 0 ]]; then
          print_success "All installed tools are already up to date!"
          exit 0
        fi
        
        if ! confirm_installation "upgrade" "${outdated_tools[@]}"; then
          exit 0
        fi
      fi
      
      # Upgrade outdated installed tools
      if [[ "$dry_run" == "true" ]]; then
        upgrade_installed true
      else
        upgrade_installed
      fi
      ;;
    "install")
      if [[ ${#tools[@]} -eq 0 ]]; then
        print_error "No tools specified for installation"
        echo "Use: $0 tool1 [tool2 ...] or $0 --install tool1 [tool2 ...]"
        exit 1
      fi
      
      # Validate tools exist
      if ! validate_tools "${tools[@]}"; then
        exit 1
      fi
      
      # Confirm installation unless dry run or skip confirm
      if [[ "$dry_run" != "true" && "$skip_confirm" != "true" ]]; then
        if ! confirm_installation "install" "${tools[@]}"; then
          exit 0
        fi
      fi
      
      # Install tools
      local total=${#tools[@]}
      for i in "${!tools[@]}"; do
        install_tool "${tools[$i]}" "$((i+1))" "$total" "$dry_run" "$force"
      done
      
      if [[ "$dry_run" != "true" ]]; then
        print_summary
      fi
      ;;
    "uninstall")
      if [[ ${#tools[@]} -eq 0 ]]; then
        print_error "No tools specified for uninstallation"
        echo "Use: $0 --uninstall tool1 [tool2 ...]"
        exit 1
      fi
      
      # Validate tools exist in config
      if ! validate_tools "${tools[@]}"; then
        exit 1
      fi
      
      # Confirm uninstallation unless dry run or skip confirm
      if [[ "$dry_run" != "true" && "$skip_confirm" != "true" ]]; then
        if ! confirm_installation "uninstall" "${tools[@]}"; then
          exit 0
        fi
      fi
      
      # Uninstall tools
      if [[ "$dry_run" == "true" ]]; then
        uninstall_tools true "${tools[@]}"
      else
        uninstall_tools "${tools[@]}"
      fi
      ;;
    "install-all")
      # Get all available tools
      mapfile -t tools < <(get_available_tools)
      
      if [[ ${#tools[@]} -eq 0 ]]; then
        print_warning "No tools found in config file"
        exit 1
      fi
      
      # Confirm installation unless dry run or skip confirm
      if [[ "$dry_run" != "true" && "$skip_confirm" != "true" ]]; then
        if ! confirm_installation "install" "${tools[@]}"; then
          exit 0
        fi
      fi
      
      # Install all tools
      local total=${#tools[@]}
      for i in "${!tools[@]}"; do
        install_tool "${tools[$i]}" "$((i+1))" "$total" "$dry_run" "$force"
      done
      
      if [[ "$dry_run" != "true" ]]; then
        print_summary
      fi
      ;;
    "uninstall-all")
      # Confirm uninstallation unless dry run or skip confirm
      if [[ "$dry_run" != "true" && "$skip_confirm" != "true" ]]; then
        # Get installed tools for confirmation
        local installed_tools=()
        mapfile -t all_tools < <(get_available_tools)
        for tool in "${all_tools[@]}"; do
          if load_tool_config "$tool"; then
            local installed_info
            installed_info=$(get_installed_info "$APPLICATION" "$VERSION_CMD_ARGS" "$VERSION_REGEX")
            local installed_path="${installed_info%%:*}"
            if [[ -n "$installed_path" ]]; then
              installed_tools+=("$tool")
            fi
          fi
        done
        
        if [[ ${#installed_tools[@]} -eq 0 ]]; then
          print_status "No tools from config are currently installed"
          exit 0
        fi
        
        if ! confirm_installation "uninstall" "${installed_tools[@]}"; then
          exit 0
        fi
      fi
      
      # Uninstall all tools
      if [[ "$dry_run" == "true" ]]; then
        uninstall_all_tools true
      else
        uninstall_all_tools
      fi
      ;;
    *)
      print_error "No action specified"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
}

# Run main function with all arguments
main "$@"