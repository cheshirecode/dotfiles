# Dotfiles

Personal configuration files for shell environments and AI-assisted development tools.

## Overview

This repository contains:
- **Shell configurations**: Bash, Zsh, and common shell utilities
- **Git configuration**: Global git settings and helpers
- **Claude Code integration**: Comprehensive development guidelines and MCP server configurations
- **OpenCode integration**: Portable global config with model routing and quantization preferences
- **Development tools**: Prettier, Stylelint, and other code quality tools

## Quick Start

### For Shell Configurations

```bash
# Clone the repository
git clone https://github.com/cheshirecode/dotfiles.git ~/.dotfiles

# Source shell configurations
source ~/.dotfiles/.bashrc  # For Bash
source ~/.dotfiles/.zshrc   # For Zsh
```

### For Claude Code

See **[SETUP-CLAUDE.md](SETUP-CLAUDE.md)** for complete setup instructions.

## OpenCode

`bin/install.sh` links `.config/opencode/opencode.jsonc` to
`~/.config/opencode/opencode.jsonc`. The committed config contains global
model defaults, OpenRouter provider ordering, quantization preferences, MCP
servers, and agent defaults. API keys and other credentials stay in environment
variables or OpenCode's local auth store and are not exported here.

**Quick links**:
- 📖 **[CLAUDE.md](CLAUDE.md)** - Comprehensive development guidelines
- ⚙️ **[claude-mcp.example.json](claude-mcp.example.json)** - MCP server configuration
- 🚀 **[SETUP-CLAUDE.md](SETUP-CLAUDE.md)** - Installation and setup guide

## Claude Code Integration

This repository includes comprehensive documentation and configurations for using Claude Code effectively in your development workflow.

### What's Included

#### Core Documentation
- **[CLAUDE.md](CLAUDE.md)** - Complete development guidelines covering:
  - Development philosophy and best practices
  - Code quality standards
  - Git workflow and commit conventions
  - Testing strategies
  - Deployment patterns
  - Quality checklists
  - **WSL-specific considerations**

#### MCP Server Configuration
- **[claude-mcp.example.json](claude-mcp.example.json)** - Example MCP server configuration
  - Core servers (sequential-thinking, filesystem)
  - Optional servers (github, web-search)
  - Experimental servers
  - **WSL and Docker integration notes**

#### Supporting Documentation (`docs/`)
- **[docs/mcp-servers.md](docs/mcp-servers.md)** - Detailed MCP server documentation
  - Setup instructions for each server
  - Authentication and API key management
  - Troubleshooting guide
  - **WSL-specific Docker setup**

- **[docs/workflows.md](docs/workflows.md)** - Reusable development workflow patterns
  - Atomic commit workflow
  - Feature development workflow
  - Test-driven development
  - Debugging investigation
  - Safe refactoring patterns
  - **WSL environment considerations**

- **[docs/tool-mapping.md](docs/tool-mapping.md)** - Cursor to Claude Code migration guide
  - Comprehensive tool mapping
  - Side-by-side examples
  - Best practices and anti-patterns
  - **WSL path handling**

### Platform Support

These configurations work on:
- ✅ **Linux** (native)
- ✅ **macOS**
- ✅ **WSL** (Windows Subsystem for Linux) - **Extensively documented**

**WSL users**: Special attention has been given to WSL-specific considerations including Docker Desktop integration, path handling, performance optimization, and troubleshooting.

### For Cursor Users

If you're migrating from Cursor, see:
1. **[docs/tool-mapping.md](docs/tool-mapping.md)** - Tool equivalents and migration guide
2. **[SETUP-CLAUDE.md](SETUP-CLAUDE.md)** - "Migration from Cursor" section

The `.cursor/` directory contains Cursor-specific configurations that are maintained separately.

## Repository Structure

```
.
├── CLAUDE.md                    # Main Claude Code development guide
├── SETUP-CLAUDE.md              # Claude Code setup instructions
├── claude-mcp.example.json      # MCP server configuration template
├── claude-code-migration.plan.md # Implementation plan (reference)
├── docs/                        # Supporting documentation
│   ├── mcp-servers.md          # MCP server details
│   ├── workflows.md            # Development workflows
│   └── tool-mapping.md         # Cursor→Claude Code mapping
├── .cursor/                     # Cursor-specific configurations
│   ├── mcp.json                # Cursor MCP config
│   └── rules/                  # Cursor AI rules
├── .bashrc                      # Bash configuration
├── .zshrc                       # Zsh configuration
├── .shell_common                # Shared shell configuration
├── .bash_profile                # Bash profile
├── .profile                     # POSIX shell profile
├── .gitconfig                   # Git configuration
├── .ssh-agent.sh                # SSH agent helper
├── .prettierrc.js               # Prettier configuration
├── .stylelintrc                 # Stylelint configuration
└── README.md                    # This file
```

## Shell Configurations

### Features

- **Shared configuration**: Common functions and aliases in `.shell_common`
- **SSH agent management**: Automatic SSH agent setup
- **Git integration**: Enhanced git aliases and helpers
- **NVM support**: Node Version Manager integration
- **Docker helpers**: Cleanup and management aliases
- **WSL compatibility**: Works seamlessly in WSL environments

### Installation

```bash
# Clone to your home directory
git clone https://github.com/cheshirecode/dotfiles.git ~/.dotfiles
cd ~/.dotfiles && bin/install.sh

# bin/install.sh is the SUPPORTED install path: detects your OS, installs
# runtime deps, runs the agent-skill installer (with the rmtree-safety
# sentinel), wires hooks, runs bin/doctor.sh. Idempotent — re-run is safe.
#
# If you want manual symlinks instead, BACK UP FIRST. `ln -sf` will
# silently overwrite an existing real ~/.bashrc / ~/.zshrc / ~/.gitconfig
# and destroy your work. Pattern that won't bite:
#   for f in .bashrc .bash_profile .zshrc; do
#     [[ -e ~/$f && ! -L ~/$f ]] && mv ~/$f ~/$f.pre-dotfiles
#   done
#   ln -sf ~/.dotfiles/.bashrc ~/.bashrc
#   ln -sf ~/.dotfiles/.bash_profile ~/.bash_profile
#   ln -sf ~/.dotfiles/.zshrc ~/.zshrc

# Reload your shell
source ~/.bashrc  # or source ~/.zshrc
```

## Git Configuration

Includes:
- Useful aliases
- Better diff and merge tools
- Credential management
- WSL-compatible settings

```bash
# Link git configuration (BACK UP your existing ~/.gitconfig first!)
[[ -e ~/.gitconfig && ! -L ~/.gitconfig ]] && mv ~/.gitconfig ~/.gitconfig.pre-dotfiles
ln -sf ~/.dotfiles/.gitconfig ~/.gitconfig
```

## Environment-Specific Notes

### WSL (Windows Subsystem for Linux)

**Important considerations for WSL users**:

1. **File System Performance**
   - Keep projects in WSL filesystem (`/home/...`) for best performance
   - Avoid working in `/mnt/c/...` when possible (slower I/O)

2. **Docker Integration**
   - Use Docker Desktop for Windows with WSL2 integration
   - See [docs/mcp-servers.md](docs/mcp-servers.md) for Docker setup

3. **Path Handling**
   - WSL uses Linux paths: `/home/user/project`
   - Windows paths accessible via: `/mnt/c/Users/...`
   - Use `wslpath` for path conversion

4. **Git Configuration**
   - Configure line endings: `git config --global core.autocrlf input`
   - Use WSL-native git (not Windows git.exe)

5. **Claude Code with WSL**
   - Config location: `~/.config/claude/mcp.json` (Linux path in WSL)
   - Docker MCP servers work with Docker Desktop integration
   - See [SETUP-CLAUDE.md](SETUP-CLAUDE.md) for detailed WSL setup

## Contributing

Feel free to open issues or submit pull requests with improvements.

When contributing:
- Follow existing code style
- Test changes in your environment
- Update documentation as needed
- Use conventional commit messages

## License

MIT License - See [LICENSE](LICENSE) file for details

## Author

[cheshirecode](https://github.com/cheshirecode)

---

## Additional Resources

### Claude Code
- [CLAUDE.md](CLAUDE.md) - Development guidelines
- [SETUP-CLAUDE.md](SETUP-CLAUDE.md) - Setup guide
- [docs/](docs/) - Detailed documentation

### External Links
- [Claude Code Documentation](https://docs.anthropic.com/claude/docs)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [WSL Documentation](https://docs.microsoft.com/windows/wsl/)
- [Docker Desktop WSL Integration](https://docs.docker.com/desktop/wsl/)

---

**Last Updated**: 2026-01-21
