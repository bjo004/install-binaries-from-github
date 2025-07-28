# GitHub Binary Installer

A powerful and intelligent bash script for automatically installing and managing command-line tools from GitHub releases. The script handles version detection, normalization, downloading, extraction, and installation with robust error handling and comprehensive toolchain management.

## 🚀 Features

- **Automatic Installation**: Install CLI tools directly from GitHub releases
- **Version Management**: Detect installed vs latest versions with smart comparison
- **Bulk Operations**: Install, upgrade, or uninstall multiple tools at once
- **Version Normalization**: Handles different version formats (`v1.2.3`, `1.2.3`, `tool-1.2.3`) seamlessly
- **Architecture Support**: Automatically detects and supports `amd64`, `arm64`, `arm`, and `386` architectures
- **Archive Handling**: Supports `.tar.gz`, `.zip`, and single binary downloads
- **Dry Run Mode**: Preview operations before execution
- **Force Reinstall**: Override version checks for debugging or rollbacks
- **Comprehensive Help**: Built-in documentation for adding new tools
- **Color Output**: Enhanced readability with color-coded status messages
- **Process Management**: Automatically stops running processes before upgrades
- **Flexible Configuration**: INI-style config file with tool definitions

## 📋 Prerequisites

The script requires these common tools (available on most Linux systems):
- `curl` - For downloading files and API calls
- `tar` - For extracting .tar.gz archives  
- `unzip` - For extracting .zip archives
- `sudo` - For installing to system directories
- `grep`, `awk`, `sed` - For text processing

## 🛠️ Installation

1. **Download the script**:
   ```bash
   wget https://your-domain.com/install_from_github.sh
   chmod +x install_from_github.sh
   ```

2. **Create or download a config file**:
   ```bash
   wget https://your-domain.com/install_from_github.config
   ```

3. **Optional: Set up GitHub token** (recommended to avoid API rate limits):
   ```bash
   export GITHUB_TOKEN="your_personal_access_token"
   ```

## 📖 Quick Start

```bash
# List available tools
./install_from_github.sh --list

# Install specific tools  
./install_from_github.sh jq yq kubectl

# Check what's installed vs latest
./install_from_github.sh --show-installed

# Upgrade all outdated tools
./install_from_github.sh --upgrade-installed

# Install all tools from config
./install_from_github.sh --install-all

# Preview what would be installed
./install_from_github.sh flux stern dive --dry-run
```

## 🎯 Usage Examples

### Basic Operations
```bash
# Install single tool
./install_from_github.sh helm -y

# Install multiple tools without confirmation
./install_from_github.sh jq yq bat fd -y

# Force reinstall existing tool
./install_from_github.sh kubectl --force -y

# Uninstall tools
./install_from_github.sh --uninstall helm kubectl
```

### Bulk Operations
```bash
# Install everything
./install_from_github.sh --install-all

# Upgrade only outdated tools
./install_from_github.sh --upgrade-installed

# Remove all managed tools
./install_from_github.sh --uninstall-all
```

### Advanced Usage
```bash
# Use custom config file
./install_from_github.sh --config /path/to/custom.config helm

# Install to custom directory
./install_from_github.sh --path /opt/bin kubectl

# Verbose output for debugging
./install_from_github.sh helm -v

# Dry run to preview actions
./install_from_github.sh --install-all --dry-run
```

## 📝 Configuration File

The script uses an INI-style configuration file (`install_from_github.config`) to define available tools:

```ini
[helm]
DESCRIPTION="Kubernetes package manager"
APPLICATION="helm"
GITHUB_REPO="helm/helm"
VERSION_CMD_ARGS="version --short"
VERSION_REGEX='v\d+\.\d+\.\d+'
ARCHIVE_PATTERN="helm-%VERSION%-linux-%ARCH%.tar.gz"
BINARY_NAME="linux-%ARCH%/helm"

[jq]
DESCRIPTION="Command-line JSON processor"
APPLICATION="jq"
GITHUB_REPO="jqlang/jq"
VERSION_CMD_ARGS="--version"
VERSION_REGEX='jq-\d+\.\d+(\.\d+)?'
ARCHIVE_PATTERN="jq-linux-amd64"
BINARY_NAME="jq-linux-amd64"
```

### Configuration Fields

- **DESCRIPTION**: Brief description of the tool
- **APPLICATION**: Binary name for PATH lookup and execution
- **GITHUB_REPO**: GitHub repository in `owner/repo` format
- **VERSION_CMD_ARGS**: Command arguments to get version (e.g., `--version`)
- **VERSION_REGEX**: Perl regex to extract version from command output
- **ARCHIVE_PATTERN**: Download filename pattern with placeholders
- **BINARY_NAME**: Path to binary inside extracted archive

### Placeholders

- **%VERSION%**: Replaced with normalized version number
- **%ARCH%**: Replaced with system architecture (`amd64`, `arm64`, etc.)

## ➕ Adding New Tools

The script includes comprehensive help for adding new tools. Run:

```bash
./install_from_github.sh --help
```

### Quick Guide

1. **Find the GitHub repository** and verify it has releases
2. **Test the version command**:
   ```bash
   tool_name --version
   # Output: "tool 1.2.3" → VERSION_REGEX='\d+\.\d+\.\d+'
   ```
3. **Check release assets** at `https://github.com/owner/repo/releases/latest`
4. **Create config entry**:
   ```ini
   [tool_name]
   DESCRIPTION="Tool description"
   APPLICATION="tool_name"
   GITHUB_REPO="owner/repo"
   VERSION_CMD_ARGS="--version"
   VERSION_REGEX='\d+\.\d+\.\d+'
   ARCHIVE_PATTERN="tool_%VERSION%_linux_amd64.tar.gz"
   BINARY_NAME="tool"
   ```
5. **Test the configuration**:
   ```bash
   ./install_from_github.sh tool_name --dry-run
   ./install_from_github.sh tool_name -y
   ```

## 🏗️ Supported Tools (Default Config)

The included configuration supports these popular DevOps and development tools:

### Kubernetes & Containers
- **k9s** - Kubernetes cluster management TUI
- **helm** - Kubernetes package manager
- **kubectl** - Kubernetes command-line tool (via other configs)
- **kind** - Kubernetes in Docker
- **stern** - Multi-pod log tailing
- **flux** - GitOps toolkit
- **argocd** - GitOps continuous delivery

### Infrastructure & Security
- **terragrunt** - Terraform wrapper
- **tenv** - Terraform/OpenTofu version manager
- **docker-compose** - Multi-container orchestration
- **trivy** - Vulnerability scanner
- **grype** - Container vulnerability scanner
- **dive** - Docker image layer explorer

### CLI Utilities
- **jq** - JSON processor
- **yq** - YAML processor  
- **bat** - Enhanced cat with syntax highlighting
- **fd** - User-friendly find alternative
- **ripgrep** - Fast grep alternative

## 🔧 Command Reference

### Installation Commands
```bash
# Basic installation
./install_from_github.sh TOOL [TOOL2 ...]

# Explicit installation
./install_from_github.sh --install TOOL [TOOL2 ...]

# Install all configured tools
./install_from_github.sh --install-all

# Force reinstall (only affects installed tools)
./install_from_github.sh TOOL --force
```

### Management Commands
```bash
# List available tools
./install_from_github.sh --list

# Show version status
./install_from_github.sh --show-installed

# Upgrade outdated tools
./install_from_github.sh --upgrade-installed

# Uninstall tools
./install_from_github.sh --uninstall TOOL [TOOL2 ...]

# Uninstall all managed tools
./install_from_github.sh --uninstall-all
```

### Options
```bash
-h, --help              Show comprehensive help
-c, --config FILE       Use custom config file
-p, --path PATH         Install to custom directory
-f, --force             Force reinstall existing tools
-d, --dry-run           Preview actions without execution
-y, --yes               Skip confirmation prompts
-v, --verbose           Show detailed output
```

## 🐛 Troubleshooting

### Common Issues

**"API rate limit exceeded"**
- Solution: Set up a GitHub personal access token
- Create token at: https://github.com/settings/tokens
- Export: `export GITHUB_TOKEN="your_token"`

**"Failed to get latest version"**
- Check if `GITHUB_REPO` is correct in config
- Verify the repository has releases
- Check internet connectivity

**"Download/extract failed"**
- Verify `ARCHIVE_PATTERN` matches actual filename on GitHub releases
- Check if the file format is supported (`.tar.gz`, `.zip`, or single binary)

**"Binary not found"**
- Check `BINARY_NAME` path is correct for the archive structure
- Use `--verbose` to see extraction details
- Manually download and extract to verify structure

**"Tool not detected after installation"**
- Ensure `VERSION_REGEX` matches the tool's version output format
- Verify `APPLICATION` name matches the installed binary name
- Check if binary is executable and in PATH

### Debug Mode

Run with verbose output to diagnose issues:
```bash
./install_from_github.sh tool_name -v
```

## 🔒 Security Considerations

- **No checksum verification**: Currently doesn't verify download integrity
- **Sudo required**: Installs to system directories requiring elevated privileges  
- **GitHub trust**: Relies on GitHub's security for download authenticity
- **Process termination**: Automatically kills running processes during upgrades

## 🚦 Limitations

- **GitHub releases only**: Only works with tools distributed via GitHub releases
- **Linux focus**: Optimized for Linux systems (some tools may work on macOS)
- **No dependency management**: Doesn't handle tool dependencies
- **No rollback**: No built-in mechanism to revert to previous versions
- **Architecture detection**: Limited to common architectures

## 🔮 Future Enhancements

- Checksum verification for downloads
- Support for additional archive formats
- Dependency management
- Configuration validation
- Version pinning
- Rollback functionality
- Windows and macOS support improvements

## 📄 License

This project is provided as-is for educational and practical use. Please ensure compliance with the licenses of the individual tools being installed.

## 🤝 Contributing

Contributions welcome! Areas for improvement:
- Additional tool configurations
- Enhanced error handling
- New features and capabilities
- Documentation improvements
- Testing and validation

---

**Note**: This tool manages external software installations. Always review what you're installing and ensure it comes from trusted sources. The script author is not responsible for the security or functionality of third-party tools.
