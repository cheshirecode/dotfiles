# MCP Servers Documentation

> Comprehensive guide to Model Context Protocol (MCP) servers for Claude Code

**Version**: 1.0.0
**Last Updated**: 2026-01-21
**Configuration File**: `claude-mcp.example.json`

---

## Table of Contents

1. [Overview](#overview)
   - [What is MCP](#what-is-mcp)
   - [Why Use MCP Servers](#why-use-mcp-servers)
   - [Architecture](#architecture)
2. [Quick Start](#quick-start)
   - [Installation](#installation)
   - [Minimal Configuration](#minimal-configuration)
   - [WSL-Specific Setup](#wsl-specific-setup)
3. [Server Categories](#server-categories)
4. [Core Servers](#core-servers)
   - [sequential-thinking](#sequential-thinking)
   - [filesystem](#filesystem)
5. [Optional Servers](#optional-servers)
   - [web-search](#web-search)
   - [github](#github)
6. [Experimental Servers](#experimental-servers)
   - [context7](#context7)
   - [browsertools](#browsertools)
   - [magic-mcp](#magic-mcp)
7. [Configuration Management](#configuration-management)
   - [File Locations](#file-locations)
   - [Environment Variables](#environment-variables)
   - [Removing Metadata](#removing-metadata)
8. [Authentication & API Keys](#authentication--api-keys)
   - [GitHub Token Setup](#github-token-setup)
   - [Web Search API Keys](#web-search-api-keys)
   - [Secure Token Storage](#secure-token-storage)
9. [WSL-Specific Considerations](#wsl-specific-considerations)
   - [Docker Desktop Integration](#docker-desktop-integration)
   - [Path Handling](#path-handling)
   - [Performance Tips](#performance-tips)
10. [Troubleshooting](#troubleshooting)
    - [Common Issues](#common-issues)
    - [Docker Problems](#docker-problems)
    - [npx/Node.js Issues](#npxnodejs-issues)
    - [Environment Variable Problems](#environment-variable-problems)
11. [Security Best Practices](#security-best-practices)
    - [Credential Management](#credential-management)
    - [Docker Security](#docker-security)
    - [Network Security](#network-security)
12. [Advanced Topics](#advanced-topics)
    - [Custom MCP Servers](#custom-mcp-servers)
    - [Server Priority & Loading Order](#server-priority--loading-order)
    - [Performance Optimization](#performance-optimization)

---

## Overview

### What is MCP

**Model Context Protocol (MCP)** is a standardized protocol that enables AI assistants like Claude to interact with external tools, services, and data sources in a secure and structured way.

**Key Concepts**:
- **Server**: A process that provides capabilities (tools, resources, prompts) to Claude
- **Client**: Claude Code acts as the MCP client, connecting to configured servers
- **Tools**: Functions that Claude can invoke (e.g., search GitHub, access files)
- **Resources**: Data sources Claude can read (e.g., documentation, databases)
- **Prompts**: Pre-configured prompt templates Claude can use

**Benefits**:
- **Extensibility**: Add new capabilities without modifying Claude Code
- **Modularity**: Enable only the servers you need
- **Standardization**: Servers follow a common protocol
- **Security**: Each server runs in isolation with defined permissions

### Why Use MCP Servers

**Enhanced Capabilities**:
- **Sequential Thinking**: Improved reasoning for complex problems
- **File System Access**: Additional file operations beyond built-in tools
- **Web Search**: Real-time information retrieval
- **GitHub Integration**: Repository management and API access
- **Context Management**: Enhanced context handling across sessions

**Use Cases**:
- Research and documentation lookup
- Repository operations (issues, PRs, releases)
- Complex problem-solving requiring multi-step reasoning
- File system operations on restricted paths
- Integration with external services

### Architecture

```
┌─────────────────────────────────────────────┐
│           Claude Code (MCP Client)          │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │      User Interaction Layer          │  │
│  └──────────────────────────────────────┘  │
│                    │                        │
│  ┌──────────────────────────────────────┐  │
│  │         MCP Client Manager           │  │
│  └──────────────────────────────────────┘  │
│         │           │           │           │
└─────────┼───────────┼───────────┼───────────┘
          │           │           │
          ▼           ▼           ▼
    ┌─────────┐ ┌─────────┐ ┌─────────┐
    │  MCP    │ │  MCP    │ │  MCP    │
    │ Server  │ │ Server  │ │ Server  │
    │   #1    │ │   #2    │ │   #3    │
    └─────────┘ └─────────┘ └─────────┘
         │           │           │
         ▼           ▼           ▼
    External    External    External
    Services    Tools       Resources
```

**Communication Flow**:
1. User makes request to Claude Code
2. Claude analyzes request and determines needed tools
3. MCP client invokes appropriate server(s)
4. Server(s) execute operations and return results
5. Claude processes results and responds to user

---

## Quick Start

### Installation

**Prerequisites**:
- Node.js 18+ (for npx-based servers)
- Docker Desktop (for Docker-based servers like GitHub)
- Claude Code installed and configured

**Step 1: Copy Example Configuration**

```bash
# Linux/WSL
cp /home/fred/projects/dotfiles/claude-mcp.example.json ~/.config/claude/mcp.json

# macOS
cp claude-mcp.example.json ~/Library/Application\ Support/Claude/mcp.json
```

**Step 2: Remove Metadata Fields**

The example configuration contains documentation fields that must be removed:
- `_comment`
- `_description`
- `_category`
- `_note`
- `_setup*` (setup instructions)
- `_wsl_note`
- `_installation_instructions`
- `_security_warnings`

See [Removing Metadata](#removing-metadata) for details.

**Step 3: Configure Servers**

Enable the servers you need by keeping them in `mcpServers` object. Remove servers you don't need.

**Step 4: Add Credentials**

For servers requiring authentication (GitHub, web-search), add your API keys/tokens.

**Step 5: Restart Claude Code**

Changes to `mcp.json` require restarting Claude Code to take effect.

### Minimal Configuration

**Recommended starting configuration** (CORE servers only):

```json
{
  "$schema": "https://modelcontextprotocol.io/schema/mcp.json",
  "mcpServers": {
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem"]
    }
  }
}
```

This provides enhanced reasoning and file system access without requiring any API keys or Docker.

### WSL-Specific Setup

**Path Configuration**:
- Use **Linux paths** in `mcp.json`: `/home/user/.config/claude/mcp.json`
- Do NOT use Windows paths: `C:\Users\...`
- Docker Desktop integration works seamlessly with WSL2

**Docker Desktop Setup**:
1. Install Docker Desktop for Windows
2. Open Docker Desktop settings
3. Navigate to **Resources** → **WSL Integration**
4. Enable integration for your WSL distribution (e.g., Ubuntu)
5. Restart WSL if needed

**Verify Docker Integration**:
```bash
# In WSL terminal
docker --version
# Should show Docker version without errors

docker ps
# Should connect to Docker Desktop daemon
```

**Environment Setup**:
```bash
# Add to ~/.bashrc or ~/.zshrc for persistent environment variables
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_your_token_here"

# Reload shell configuration
source ~/.bashrc  # or source ~/.zshrc
```

---

## Server Categories

MCP servers are organized into three categories based on stability and recommended usage:

| Category | Description | Stability | Recommended For |
|----------|-------------|-----------|-----------------|
| **CORE** | Essential servers, recommended for all users | Stable | All users |
| **OPTIONAL** | Useful servers for specific use cases | Stable | Users needing specific features |
| **EXPERIMENTAL** | Untested or unstable servers | Unstable | Advanced users, testing |

**Category Selection Guide**:

**Start with CORE** servers:
- `sequential-thinking`: Enhanced reasoning
- `filesystem`: Extended file operations

**Add OPTIONAL** servers as needed:
- `web-search`: For research and documentation lookup
- `github`: For GitHub repository management

**Avoid EXPERIMENTAL** unless:
- You're testing new features
- You understand the risks
- You can troubleshoot issues independently

---

## Core Servers

### sequential-thinking

**Enhanced reasoning and problem-solving capabilities for complex tasks.**

#### Overview

The sequential-thinking server provides Claude with structured thinking capabilities for multi-step problem solving, complex analysis, and systematic reasoning.

#### Configuration

```json
{
  "sequential-thinking": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
  }
}
```

#### Features

- **Multi-step Reasoning**: Break down complex problems into logical steps
- **Systematic Analysis**: Structured approach to problem-solving
- **Decision Trees**: Evaluate multiple solution paths
- **Verification**: Built-in verification of reasoning steps

#### Use Cases

- Complex code refactoring decisions
- Architecture planning and design
- Debugging intricate issues
- Performance optimization strategies
- Security vulnerability analysis

#### Requirements

- Node.js 18+
- npm or npx (included with Node.js)

#### Installation

No additional setup required. The server is automatically downloaded and executed via `npx` when Claude Code starts.

#### WSL Considerations

Works seamlessly in WSL. Uses Node.js from WSL environment.

#### Troubleshooting

**Issue**: Server fails to start
```bash
# Verify Node.js installation
node --version  # Should be 18+
npx --version

# Clear npx cache
rm -rf ~/.npm/_npx

# Test manual execution
npx -y @modelcontextprotocol/server-sequential-thinking
```

**Issue**: Performance degradation
- The server is lightweight and shouldn't impact performance
- If issues persist, check Node.js memory usage
- Consider restarting Claude Code

---

### filesystem

**Extended file system access and manipulation beyond Claude Code's built-in tools.**

#### Overview

The filesystem server provides additional file system operations that complement Claude Code's built-in file tools (Read, Write, Edit, Glob, Grep).

#### Configuration

```json
{
  "filesystem": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-filesystem"]
  }
}
```

#### Features

- **Directory Operations**: Create, list, remove directories
- **File Metadata**: Access file stats, permissions, timestamps
- **Bulk Operations**: Process multiple files efficiently
- **Path Resolution**: Resolve symbolic links, relative paths
- **Watch Operations**: Monitor file system changes

#### Use Cases

- Directory structure management
- File permission modifications
- Bulk file operations
- File system monitoring
- Accessing restricted paths (with proper permissions)

#### Requirements

- Node.js 18+
- npm or npx
- File system permissions for target directories

#### Installation

No additional setup required. Downloads automatically via `npx`.

#### WSL Considerations

**Path Access**:
- Can access both WSL (`/home/...`) and Windows (`/mnt/c/...`) paths
- Performance is better on native WSL filesystem
- Windows path access subject to Windows permissions

**Permissions**:
- Respects Linux file permissions in WSL
- May require elevated permissions for system directories
- Use `chmod` to adjust permissions if needed

#### Security Notes

- Only grant filesystem access to trusted directories
- Consider using path restrictions in server configuration
- Be cautious with write operations on critical system files
- Regularly audit file system operations in logs

#### Troubleshooting

**Issue**: Permission denied
```bash
# Check file permissions
ls -la /path/to/file

# Adjust permissions if needed
chmod 644 /path/to/file  # Read/write for owner, read for others
chmod 755 /path/to/directory  # Execute permission for directories
```

**Issue**: Path not found (WSL)
```bash
# Verify Windows path is accessible
ls /mnt/c/Users/YourName/

# Convert Windows path to WSL path
wslpath 'C:\Users\YourName\project'
```

---

## Optional Servers

### web-search

**Web search capabilities for finding documentation, solutions, and current information.**

#### Overview

The web-search server enables Claude to search the web for up-to-date information, documentation, troubleshooting guides, and technical solutions.

#### Configuration

```json
{
  "web-search": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-web-search"]
  }
}
```

#### Features

- **Real-time Search**: Access current information beyond Claude's training data
- **Documentation Lookup**: Find official documentation and API references
- **Troubleshooting**: Search for error messages and solutions
- **Technology Research**: Investigate libraries, frameworks, and tools

#### Use Cases

- Looking up recent library versions
- Finding error message solutions
- Researching new technologies
- Accessing API documentation
- Verifying best practices

#### Requirements

- Node.js 18+
- API key from supported search provider
- Internet connection

#### API Key Setup

**Note**: Check the official MCP documentation for supported search providers and API key requirements.

**Common providers**:
- Google Custom Search API
- Bing Search API
- DuckDuckGo API
- Brave Search API

**Configuration with API key**:
```json
{
  "web-search": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-web-search"],
    "env": {
      "SEARCH_API_KEY": "your_api_key_here"
    }
  }
}
```

**Environment variable approach**:
```bash
# Add to ~/.bashrc or ~/.zshrc
export SEARCH_API_KEY="your_api_key_here"

# Reload shell
source ~/.bashrc
```

Then reference in `mcp.json`:
```json
{
  "web-search": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-web-search"]
  }
}
```

#### WSL Considerations

- Works identically to Linux setup
- Use Linux environment variables
- Internet connectivity through Windows network stack

#### Security Notes

- **Never commit API keys to git**
- Use environment variables for API keys
- Rotate keys regularly
- Monitor API usage and quotas
- Be aware of search provider privacy policies

#### Troubleshooting

**Issue**: API key not recognized
```bash
# Verify environment variable
echo $SEARCH_API_KEY

# Check mcp.json syntax
cat ~/.config/claude/mcp.json | jq .mcpServers.web-search

# Test API key directly
curl -H "Authorization: Bearer $SEARCH_API_KEY" https://api.example.com/test
```

**Issue**: Rate limiting
- Check API provider dashboard for quota limits
- Implement request throttling
- Upgrade API plan if needed
- Cache search results when possible

---

### github

**GitHub API integration for repository operations, issues, pull requests, and more.**

#### Overview

The GitHub MCP server provides comprehensive GitHub integration, allowing Claude to interact with repositories, issues, pull requests, releases, and other GitHub resources.

#### Configuration

```json
{
  "github": {
    "command": "docker",
    "args": [
      "run",
      "-i",
      "--rm",
      "-e",
      "GITHUB_PERSONAL_ACCESS_TOKEN",
      "ghcr.io/github/github-mcp-server"
    ],
    "env": {
      "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_your_token_here"
    }
  }
}
```

#### Features

- **Repository Management**: Create, clone, configure repositories
- **Issues**: Create, update, search, close issues
- **Pull Requests**: Create, review, merge pull requests
- **Releases**: Create and manage releases
- **Branch Operations**: Create, delete, merge branches
- **Search**: Advanced GitHub search across repos, code, issues
- **Actions**: Trigger and monitor GitHub Actions workflows

#### Use Cases

- Creating issues from bug reports
- Automating pull request creation
- Searching across organization repositories
- Managing releases and tags
- Reviewing code and pull requests
- Monitoring workflow runs

#### Requirements

- **Docker Desktop**: Required for running the server container
- **GitHub Token**: Personal access token with appropriate scopes
- **Internet Connection**: For GitHub API access

#### GitHub Token Setup

**Step 1: Create Personal Access Token**

1. Go to [https://github.com/settings/tokens](https://github.com/settings/tokens)
2. Click **"Generate new token"** → **"Generate new token (classic)"**
3. Give your token a descriptive name: `claude-code-mcp`
4. Set expiration (recommend 90 days for security)
5. Select scopes (see below)
6. Click **"Generate token"**
7. **Copy the token immediately** (you won't see it again)

**Required Scopes**:

| Scope | Purpose | Required |
|-------|---------|----------|
| `repo` | Full repository access | ✅ Yes |
| `read:org` | Read organization data | Recommended |
| `read:user` | Read user profile data | Recommended |
| `workflow` | GitHub Actions workflow access | If using Actions |

**Minimal scopes** (read-only access):
- `public_repo` (for public repositories only)
- `read:user`

**Step 2: Configure Token**

**Option A: Environment Variable (Recommended)**
```bash
# Add to ~/.bashrc or ~/.zshrc
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_your_token_here"

# Reload shell
source ~/.bashrc
```

Update `mcp.json` to use environment variable:
```json
{
  "github": {
    "command": "docker",
    "args": [
      "run",
      "-i",
      "--rm",
      "-e",
      "GITHUB_PERSONAL_ACCESS_TOKEN",
      "ghcr.io/github/github-mcp-server"
    ]
  }
}
```

**Option B: Direct Configuration (Less Secure)**
```json
{
  "github": {
    "command": "docker",
    "args": [
      "run",
      "-i",
      "--rm",
      "-e",
      "GITHUB_PERSONAL_ACCESS_TOKEN=ghp_your_token_here",
      "ghcr.io/github/github-mcp-server"
    ]
  }
}
```

⚠️ **Warning**: If using Option B, ensure `mcp.json` is not committed to git!

**Step 3: Verify Token**
```bash
# Test token directly
curl -H "Authorization: Bearer ghp_your_token_here" \
  https://api.github.com/user

# Should return your GitHub user information
```

#### Docker Setup

**Install Docker Desktop**:
- Download from [https://www.docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop)
- Install for your platform (Windows, macOS, Linux)
- Start Docker Desktop

**Verify Docker**:
```bash
docker --version
docker ps  # Should list running containers (may be empty)
```

**Pull GitHub MCP Server Image** (optional, auto-pulled on first use):
```bash
docker pull ghcr.io/github/github-mcp-server
```

#### WSL-Specific Setup

**Docker Desktop Integration**:

1. Install Docker Desktop for Windows
2. Open Docker Desktop → **Settings**
3. Navigate to **Resources** → **WSL Integration**
4. Enable **"Enable integration with my default WSL distro"**
5. Enable integration for your specific distribution (e.g., Ubuntu)
6. Click **"Apply & Restart"**

**Verify WSL Integration**:
```bash
# In WSL terminal
docker --version
# Should show Docker version

docker ps
# Should connect to Docker Desktop daemon

docker info | grep "Operating System"
# Should show "Docker Desktop"
```

**Common WSL Issues**:

**Issue**: Docker command not found
```bash
# Ensure Docker Desktop integration is enabled
# Restart WSL
wsl --shutdown
# Open WSL again and test
```

**Issue**: Docker daemon not running
```bash
# Start Docker Desktop (Windows application)
# Wait for "Docker Desktop is running" message
# Test connection from WSL
docker ps
```

**Issue**: Permission denied
```bash
# Add user to docker group (if needed)
sudo usermod -aG docker $USER

# Logout and login to WSL
exit
# Open new WSL terminal
```

#### Container Behavior

**Container Lifecycle**:
- Container starts when Claude Code invokes GitHub server
- Runs interactively (`-i` flag)
- Automatically removed when finished (`--rm` flag)
- Fresh container for each session (no state persistence)

**Performance Considerations**:
- First run: Downloads container image (~200MB)
- Subsequent runs: Fast (image is cached)
- Each invocation: 1-2 second startup time

**Resource Usage**:
- Memory: ~50-100MB per container
- CPU: Minimal when idle
- Network: Only during GitHub API calls

#### Security Notes

**Token Security**:
- ✅ Use environment variables
- ✅ Set token expiration (90 days recommended)
- ✅ Use minimal required scopes
- ✅ Rotate tokens regularly
- ❌ Never commit tokens to git
- ❌ Don't share tokens in logs/screenshots

**Docker Security**:
- Container runs with limited permissions
- No filesystem access beyond configuration
- Network isolated to GitHub API endpoints
- Environment variables visible to container only

**Monitoring**:
```bash
# Check GitHub token usage
# Visit: https://github.com/settings/tokens

# View Docker container logs
docker logs <container_id>

# Monitor API rate limits
curl -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
  https://api.github.com/rate_limit
```

#### Troubleshooting

**Issue**: Container fails to start
```bash
# Check Docker is running
docker ps

# Check container image exists
docker images | grep github-mcp-server

# Pull image manually
docker pull ghcr.io/github/github-mcp-server

# Check Docker logs
docker logs <container_id>
```

**Issue**: Authentication failed
```bash
# Verify token is set
echo $GITHUB_PERSONAL_ACCESS_TOKEN

# Test token validity
curl -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
  https://api.github.com/user

# Check token scopes
# Visit: https://github.com/settings/tokens
```

**Issue**: Rate limiting
- GitHub API has rate limits: 5000 requests/hour (authenticated)
- Check current limit: `curl -H "Authorization: Bearer $TOKEN" https://api.github.com/rate_limit`
- Wait for limit reset or optimize requests
- Consider using conditional requests (ETag)

**Issue**: WSL Docker integration broken
```bash
# Restart Docker Desktop (Windows app)

# Shutdown WSL
wsl --shutdown

# Restart Docker Desktop

# Open WSL and test
docker ps
```

#### Examples

**Create an Issue**:
```
Claude, create a GitHub issue in myorg/myrepo titled "Bug: Login fails on mobile" with description "Users report login failure on iOS devices"
```

**Search Code**:
```
Claude, search for "database connection" in myorg/myrepo
```

**Create Pull Request**:
```
Claude, create a PR from feature/new-button to main in myorg/myrepo
```

---

## Experimental Servers

⚠️ **Warning**: Experimental servers are untested or unstable. Use at your own risk. Compatibility with Claude Code is not guaranteed.

### context7

**Context management with Upstash for enhanced context handling across sessions.**

#### Overview

The context7 server provides advanced context management capabilities using Upstash's cloud infrastructure.

#### Configuration

```json
{
  "context7": {
    "command": "npx",
    "args": ["-y", "@upstash/context7-mcp@latest"]
  }
}
```

#### Status

- **Stability**: Experimental
- **Testing**: Not tested with Claude Code
- **Documentation**: [https://github.com/upstash/context7-mcp](https://github.com/upstash/context7-mcp)

#### Requirements

- Node.js 18+
- Upstash account (may require API keys)
- Additional configuration (see upstream documentation)

#### Notes

- May require additional setup beyond MCP configuration
- Compatibility with Claude Code not verified
- Check upstream repository for latest requirements
- Use at your own risk

---

### browsertools

**Browser automation capabilities for web scraping and testing.**

#### Overview

The browsertools server provides browser automation capabilities, potentially including page scraping, screenshot capture, and web testing.

#### Configuration

```json
{
  "browsertools": {
    "command": "npx",
    "args": ["@agentdeskai/browser-tools-mcp"]
  }
}
```

#### Status

- **Stability**: Experimental
- **Testing**: Not tested with Claude Code
- **Documentation**: Limited

#### Requirements

- Node.js 18+
- Potentially Puppeteer or Playwright dependencies
- Additional system dependencies (Chrome/Chromium)

#### Notes

- May require headless browser installation
- Resource-intensive operations
- Compatibility unknown
- Use at your own risk

---

### magic-mcp

**Magic MCP server for enhanced capabilities.**

#### Overview

The magic-mcp server provides additional capabilities for Claude. Specific features are not well documented.

#### Configuration

```json
{
  "magic-mcp": {
    "command": "npx",
    "args": ["-y", "@21st-dev/magic-mcp"]
  }
}
```

#### Status

- **Stability**: Experimental
- **Testing**: Not tested with Claude Code
- **Documentation**: Limited

#### Requirements

- Node.js 18+
- Unknown additional requirements

#### Notes

- Features not clearly documented
- Compatibility unknown
- Use at your own risk
- Check npm package for latest information

---

## Configuration Management

### File Locations

**Linux/WSL**:
```
~/.config/claude/mcp.json
/home/username/.config/claude/mcp.json
```

**macOS**:
```
~/Library/Application Support/Claude/mcp.json
/Users/username/Library/Application Support/Claude/mcp.json
```

**Windows**: Not applicable - Use WSL for Claude Code on Windows

### Environment Variables

Environment variables can be defined in two ways:

**Option 1: In mcp.json (less secure)**
```json
{
  "github": {
    "command": "docker",
    "args": [...],
    "env": {
      "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_your_token_here"
    }
  }
}
```

**Option 2: System environment (recommended)**
```bash
# Add to ~/.bashrc or ~/.zshrc
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_your_token_here"
export SEARCH_API_KEY="your_search_key_here"

# Reload shell
source ~/.bashrc
```

**Precedence**:
1. Environment variables defined in `mcp.json` `env` object (highest)
2. System environment variables
3. Default values (if any)

### Removing Metadata

The example configuration file contains documentation fields prefixed with `_` that must be removed before use:

**Fields to Remove**:
- `_comment`
- `_description`
- `_category`
- `_note`
- `_setup`, `_setup2`, `_setup3`, etc.
- `_wsl_note`
- `_installation_instructions`
- `_security_warnings`

**Automated Removal** (using jq):
```bash
# Remove all _ fields
jq 'walk(if type == "object" then with_entries(select(.key | startswith("_") | not)) else . end)' \
  claude-mcp.example.json > ~/.config/claude/mcp.json
```

**Manual Removal**:
Open in text editor and delete all lines containing `"_...": ...`

**Validation**:
```bash
# Check JSON syntax
jq . ~/.config/claude/mcp.json

# Should show clean configuration without _ fields
```

---

## Authentication & API Keys

### GitHub Token Setup

See [github server documentation](#github-token-setup) for detailed setup.

**Quick Reference**:
1. Create token at [https://github.com/settings/tokens](https://github.com/settings/tokens)
2. Select `repo` scope (minimum)
3. Copy token (shown only once)
4. Add to environment: `export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_..."`
5. Update `mcp.json` to reference environment variable

**Token Rotation**:
```bash
# Create new token on GitHub
# Update environment variable
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_new_token_here"

# Update ~/.bashrc or ~/.zshrc for persistence
echo 'export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_new_token_here"' >> ~/.bashrc

# Restart Claude Code
```

### Web Search API Keys

**Provider Selection**:
- Check MCP documentation for supported providers
- Compare pricing and rate limits
- Consider privacy implications

**Setup Process**:
1. Sign up for search API provider
2. Create API key
3. Configure in environment variable or `mcp.json`
4. Test API key validity
5. Monitor usage and quotas

### Secure Token Storage

**Best Practices**:

1. **Environment Variables** (Recommended)
   ```bash
   # Add to ~/.bashrc (persistent)
   export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_..."
   export SEARCH_API_KEY="sk_..."
   ```

2. **Secret Management Tools** (Advanced)
   - Use password managers (pass, 1Password CLI)
   - Use secret management services (HashiCorp Vault)
   - Use OS keychain (gnome-keyring, macOS Keychain)

3. **File Permissions**
   ```bash
   # Restrict mcp.json to user only
   chmod 600 ~/.config/claude/mcp.json
   ```

4. **Git Ignore**
   ```bash
   # If mcp.json contains secrets, add to .gitignore
   echo '*.config/claude/mcp.json' >> ~/.gitignore_global

   # Or keep secrets in separate file
   echo '.env.mcp' >> ~/.gitignore
   ```

**What NOT to Do**:
- ❌ Commit tokens to git repositories
- ❌ Share tokens in screenshots/logs
- ❌ Use tokens in public documentation
- ❌ Store tokens in plaintext in cloud storage
- ❌ Use production tokens for testing

**Audit**:
```bash
# Check git history for accidentally committed secrets
git log -p | grep -i "ghp_\|sk_\|token"

# Use tools like git-secrets to prevent commits
git secrets --scan
```

---

## WSL-Specific Considerations

### Docker Desktop Integration

**Setup Requirements**:
1. Windows 10/11 with WSL2 enabled
2. Docker Desktop for Windows installed
3. WSL integration enabled in Docker Desktop settings

**Configuration Steps**:
```bash
# 1. Verify WSL version
wsl --version
# Should show WSL version 2.x.x

# 2. Check WSL distribution
wsl -l -v
# Should show your distro running Version 2

# 3. Start Docker Desktop (Windows application)

# 4. Enable WSL integration:
#    Docker Desktop → Settings → Resources → WSL Integration
#    - Enable "Enable integration with my default WSL distro"
#    - Enable integration for your distro (e.g., Ubuntu)

# 5. Verify from WSL
docker --version
docker ps
docker run hello-world
```

**Troubleshooting Docker Integration**:

**Issue**: "Cannot connect to Docker daemon"
```bash
# Check Docker Desktop is running (Windows)
# Look for Docker icon in system tray

# Restart WSL
wsl --shutdown
# Start WSL again

# Test connection
docker ps
```

**Issue**: WSL integration disabled
```bash
# In Docker Desktop (Windows app):
# Settings → Resources → WSL Integration
# Ensure your distro is checked

# Click "Apply & Restart"

# Restart WSL
wsl --shutdown
```

**Issue**: Permission denied
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Logout and login to WSL
exit
# Open new WSL terminal

# Verify
docker ps
```

### Path Handling

**WSL Path Types**:

1. **Native WSL paths**: `/home/user/...`
   - Fastest performance
   - Full Linux permissions
   - Recommended for development

2. **Windows paths via mount**: `/mnt/c/Users/...`
   - Slower performance (cross-filesystem)
   - Windows file permissions
   - Use for accessing Windows files

3. **UNC paths**: `\\wsl$\Ubuntu\home\user\...`
   - Access WSL files from Windows
   - Useful for Windows applications

**Path Conversion**:
```bash
# Windows to WSL
wslpath 'C:\Users\Fred\Documents'
# Output: /mnt/c/Users/Fred/Documents

# WSL to Windows
wslpath -w /home/fred/projects
# Output: \\wsl$\Ubuntu\home\fred\projects
```

**Best Practices**:
- Keep projects in WSL filesystem (`/home/...`)
- Avoid `/mnt/c/...` for active development
- Use WSL paths in `mcp.json`
- Use `wslpath` for conversion when needed

**Example mcp.json with paths**:
```json
{
  "filesystem": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-filesystem"],
    "env": {
      "PROJECT_ROOT": "/home/fred/projects"
    }
  }
}
```

### Performance Tips

**Optimize WSL Performance**:

1. **Use Native Filesystem**
   ```bash
   # Good: Native WSL
   cd /home/fred/projects
   git clone https://github.com/...

   # Avoid: Windows mount
   cd /mnt/c/Users/Fred/projects
   ```

2. **Configure Windows Defender Exclusions**
   ```
   # Add to Windows Defender exclusions:
   - WSL directory: C:\Users\YourName\AppData\Local\Packages\CanonicalGroupLimited...
   - Or exclude entire WSL: \\wsl$\Ubuntu\home\...
   ```

3. **Use WSL2 (not WSL1)**
   ```bash
   # Check version
   wsl -l -v

   # Upgrade to WSL2 if needed
   wsl --set-version Ubuntu 2
   ```

4. **Limit WSL Memory**
   ```
   # Create/edit: C:\Users\YourName\.wslconfig
   [wsl2]
   memory=8GB
   processors=4
   swap=2GB
   ```

5. **Enable Docker BuildKit**
   ```bash
   # Add to ~/.bashrc
   export DOCKER_BUILDKIT=1
   ```

**Benchmarking**:
```bash
# Test filesystem performance
time dd if=/dev/zero of=testfile bs=1M count=1024

# Compare WSL vs Windows mount
cd /home/fred && time dd if=/dev/zero of=testfile bs=1M count=1024
cd /mnt/c/Users/Fred && time dd if=/dev/zero of=testfile bs=1M count=1024
```

---

## Troubleshooting

### Common Issues

#### Server Fails to Start

**Symptoms**:
- MCP server not responding
- Claude Code shows server error
- Timeout on server initialization

**Diagnosis**:
```bash
# Check server configuration
cat ~/.config/claude/mcp.json | jq .mcpServers

# Test server manually
npx -y @modelcontextprotocol/server-sequential-thinking

# Check logs (if available)
journalctl --user -u claude-code  # systemd
```

**Solutions**:

1. **Verify JSON syntax**
   ```bash
   jq . ~/.config/claude/mcp.json
   # Should output valid JSON without errors
   ```

2. **Check Node.js version**
   ```bash
   node --version  # Should be 18+
   ```

3. **Clear npx cache**
   ```bash
   rm -rf ~/.npm/_npx
   ```

4. **Restart Claude Code**
   ```bash
   # Close and reopen Claude Code
   # Or restart from command line if applicable
   ```

#### Authentication Errors

**Symptoms**:
- "Invalid token" or "Unauthorized" errors
- API calls fail with 401/403

**Diagnosis**:
```bash
# Check environment variable
echo $GITHUB_PERSONAL_ACCESS_TOKEN

# Test token directly
curl -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
  https://api.github.com/user
```

**Solutions**:

1. **Verify token is set**
   ```bash
   # Check current session
   env | grep TOKEN

   # Check persistent configuration
   grep TOKEN ~/.bashrc ~/.zshrc
   ```

2. **Reload environment**
   ```bash
   source ~/.bashrc
   # or
   source ~/.zshrc
   ```

3. **Test token validity**
   ```bash
   # Visit GitHub to verify token still exists
   # https://github.com/settings/tokens
   ```

4. **Recreate token**
   - Generate new token on GitHub
   - Update environment variable
   - Restart Claude Code

### Docker Problems

#### Docker Daemon Not Running

**Symptoms**:
- "Cannot connect to Docker daemon"
- Docker commands fail

**Solutions**:

**Linux**:
```bash
# Start Docker service
sudo systemctl start docker

# Enable auto-start
sudo systemctl enable docker
```

**WSL**:
```bash
# Ensure Docker Desktop (Windows) is running
# Check system tray for Docker icon

# Restart WSL if needed
wsl --shutdown
# Open WSL again
```

**macOS**:
```bash
# Start Docker Desktop application
open -a Docker
```

#### Container Fails to Start

**Symptoms**:
- GitHub server doesn't respond
- Container exits immediately

**Diagnosis**:
```bash
# List recent containers (including stopped)
docker ps -a

# Check container logs
docker logs <container_id>

# Inspect container
docker inspect <container_id>
```

**Solutions**:

1. **Pull latest image**
   ```bash
   docker pull ghcr.io/github/github-mcp-server
   ```

2. **Check environment variables**
   ```bash
   # Test container manually
   docker run -it --rm \
     -e GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_PERSONAL_ACCESS_TOKEN" \
     ghcr.io/github/github-mcp-server
   ```

3. **Remove old containers**
   ```bash
   docker container prune
   ```

4. **Reset Docker**
   ```bash
   # Docker Desktop: Troubleshoot → Reset to factory defaults
   # Or remove and reinstall Docker
   ```

#### Image Pull Failures

**Symptoms**:
- "Unable to find image"
- "Error pulling image"

**Solutions**:

1. **Check network connectivity**
   ```bash
   ping ghcr.io
   curl https://ghcr.io
   ```

2. **Check Docker Hub rate limits**
   ```bash
   # Login to Docker Hub
   docker login
   ```

3. **Use alternative registry** (if available)
   ```bash
   # Check if image is available elsewhere
   docker search github-mcp-server
   ```

4. **Manual download and import**
   ```bash
   # Download image archive
   # Import with docker load
   ```

### npx/Node.js Issues

#### npx Command Not Found

**Solutions**:
```bash
# Install Node.js and npm
# Ubuntu/Debian
sudo apt update
sudo apt install nodejs npm

# macOS (Homebrew)
brew install node

# Verify installation
node --version
npm --version
npx --version
```

#### Version Mismatch

**Symptoms**:
- "Unsupported Node.js version"
- Syntax errors in server code

**Solutions**:

1. **Use version manager**
   ```bash
   # Install nvm (Node Version Manager)
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

   # Install Node.js 18+
   nvm install 18
   nvm use 18
   nvm alias default 18
   ```

2. **Verify version**
   ```bash
   node --version  # Should be v18.x.x or higher
   ```

#### Package Download Failures

**Symptoms**:
- "Failed to download package"
- Network timeouts

**Solutions**:

1. **Clear npm cache**
   ```bash
   npm cache clean --force
   rm -rf ~/.npm/_npx
   ```

2. **Use alternative registry**
   ```bash
   npm config set registry https://registry.npmmirror.com
   # or
   npm config set registry https://registry.npmjs.org
   ```

3. **Check network/firewall**
   ```bash
   # Test npm registry access
   curl https://registry.npmjs.org/@modelcontextprotocol/server-sequential-thinking
   ```

### Environment Variable Problems

#### Variables Not Recognized

**Symptoms**:
- Server can't find API key
- "Undefined environment variable"

**Diagnosis**:
```bash
# Check if variable is set
echo $GITHUB_PERSONAL_ACCESS_TOKEN
env | grep GITHUB

# Check where it's defined
grep GITHUB_PERSONAL_ACCESS_TOKEN ~/.bashrc ~/.zshrc ~/.profile
```

**Solutions**:

1. **Reload shell configuration**
   ```bash
   source ~/.bashrc
   # or
   source ~/.zshrc
   ```

2. **Export variables**
   ```bash
   # Ensure export keyword is used
   export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_..."
   # not just:
   # GITHUB_PERSONAL_ACCESS_TOKEN="ghp_..."
   ```

3. **Check shell initialization**
   ```bash
   # Different shells load different files
   # Bash: ~/.bashrc, ~/.bash_profile
   # Zsh: ~/.zshrc
   # Check which shell you're using
   echo $SHELL
   ```

4. **System-wide environment** (if needed)
   ```bash
   # Add to /etc/environment (requires sudo)
   sudo nano /etc/environment
   # Add line: GITHUB_PERSONAL_ACCESS_TOKEN="ghp_..."

   # Logout and login for changes to take effect
   ```

---

## Security Best Practices

### Credential Management

**API Keys and Tokens**:

1. **Use Environment Variables**
   ```bash
   # Good: Environment variable
   export API_KEY="secret_value"

   # Bad: Hardcoded in config
   "env": { "API_KEY": "secret_value" }
   ```

2. **Restrict File Permissions**
   ```bash
   # mcp.json should be readable only by user
   chmod 600 ~/.config/claude/mcp.json

   # Verify permissions
   ls -la ~/.config/claude/mcp.json
   # Should show: -rw------- (600)
   ```

3. **Use Secret Management Tools**
   ```bash
   # Example: Using pass (password manager)
   export GITHUB_TOKEN=$(pass show github/mcp-token)

   # Example: Using 1Password CLI
   export GITHUB_TOKEN=$(op read "op://Private/GitHub MCP/token")
   ```

4. **Rotate Credentials Regularly**
   - Set expiration dates on tokens (90 days recommended)
   - Create calendar reminders for rotation
   - Document rotation procedures
   - Revoke old tokens after rotation

**Git Safety**:

```bash
# Add to .gitignore
echo '.config/claude/mcp.json' >> ~/.gitignore_global
echo '.env' >> ~/.gitignore_global
echo '.env.*' >> ~/.gitignore_global

# Check for accidentally committed secrets
git log -p | grep -E "ghp_|sk_|token|api.?key" -i

# Use git-secrets to prevent commits
git secrets --install
git secrets --register-aws  # or custom patterns
```

**Audit Trail**:

```bash
# Monitor token usage on GitHub
# Visit: https://github.com/settings/tokens
# Click on token to see last used time

# Review API rate limits
curl -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
  https://api.github.com/rate_limit

# Check for suspicious activity
# GitHub: Settings → Security log
```

### Docker Security

**Container Isolation**:

1. **Use Minimal Permissions**
   ```json
   {
     "github": {
       "command": "docker",
       "args": [
         "run",
         "-i",
         "--rm",
         "--read-only",  // Read-only filesystem
         "--security-opt=no-new-privileges",  // Prevent privilege escalation
         "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
         "ghcr.io/github/github-mcp-server"
       ]
     }
   }
   ```

2. **Limit Resources**
   ```json
   {
     "github": {
       "command": "docker",
       "args": [
         "run",
         "-i",
         "--rm",
         "--memory=256m",  // Limit memory
         "--cpus=0.5",     // Limit CPU
         "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
         "ghcr.io/github/github-mcp-server"
       ]
     }
   }
   ```

3. **Network Isolation** (if needed)
   ```bash
   # Create isolated network
   docker network create mcp-isolated

   # Run container on isolated network
   docker run --network=mcp-isolated ...
   ```

**Image Security**:

```bash
# Verify image signatures (if available)
docker trust inspect ghcr.io/github/github-mcp-server

# Scan for vulnerabilities
docker scan ghcr.io/github/github-mcp-server

# Keep images updated
docker pull ghcr.io/github/github-mcp-server
```

**Container Monitoring**:

```bash
# List running containers
docker ps

# Monitor resource usage
docker stats

# Check container logs for suspicious activity
docker logs <container_id> | grep -E "error|fail|unauthorized" -i
```

### Network Security

**Firewall Configuration**:

```bash
# Allow only necessary outbound connections
# GitHub API: api.github.com (HTTPS)
# npm registry: registry.npmjs.org (HTTPS)
# Docker registry: ghcr.io (HTTPS)

# Block unnecessary inbound connections
# MCP servers typically don't need inbound access
```

**TLS/SSL Verification**:

```bash
# Ensure TLS certificate verification is enabled
# Node.js should verify by default

# Check npm SSL configuration
npm config get strict-ssl  # Should be true

# If needed, enforce strict SSL
npm config set strict-ssl true
```

**Proxy Configuration** (if needed):

```bash
# Configure HTTP proxy
export HTTP_PROXY="http://proxy.example.com:8080"
export HTTPS_PROXY="http://proxy.example.com:8080"
export NO_PROXY="localhost,127.0.0.1"

# Configure for npm
npm config set proxy http://proxy.example.com:8080
npm config set https-proxy http://proxy.example.com:8080

# Configure for Docker
# Edit ~/.docker/config.json
{
  "proxies": {
    "default": {
      "httpProxy": "http://proxy.example.com:8080",
      "httpsProxy": "http://proxy.example.com:8080",
      "noProxy": "localhost,127.0.0.1"
    }
  }
}
```

**Rate Limiting and Monitoring**:

```bash
# Monitor API usage to detect anomalies
# GitHub API limits: 5000 req/hour (authenticated)

# Check current usage
curl -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
  https://api.github.com/rate_limit

# Set up alerts for unusual usage patterns
# (Implementation depends on monitoring tools)
```

---

## Advanced Topics

### Custom MCP Servers

**Creating a Custom Server**:

MCP servers follow the Model Context Protocol specification. You can create custom servers for specialized integrations.

**Basic Structure**:
```typescript
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';

const server = new Server({
  name: 'my-custom-server',
  version: '1.0.0',
});

// Define tools
server.setRequestHandler('tools/list', async () => ({
  tools: [
    {
      name: 'my_tool',
      description: 'Description of what this tool does',
      inputSchema: {
        type: 'object',
        properties: {
          param1: { type: 'string' },
        },
        required: ['param1'],
      },
    },
  ],
}));

// Handle tool calls
server.setRequestHandler('tools/call', async (request) => {
  if (request.params.name === 'my_tool') {
    // Implement tool logic
    return {
      content: [{ type: 'text', text: 'Result' }],
    };
  }
});

// Start server
const transport = new StdioServerTransport();
await server.connect(transport);
```

**Configuration**:
```json
{
  "my-custom-server": {
    "command": "node",
    "args": ["/path/to/my-server.js"]
  }
}
```

**Resources**:
- MCP Specification: [https://modelcontextprotocol.io](https://modelcontextprotocol.io)
- MCP SDK: [@modelcontextprotocol/sdk](https://www.npmjs.com/package/@modelcontextprotocol/sdk)
- Examples: [https://github.com/modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers)

### Server Priority & Loading Order

**Server Load Behavior**:
- Servers are loaded when Claude Code starts
- Load order is not guaranteed (JSON object keys are unordered)
- Servers run independently and in parallel

**If priority matters**:
1. Use server prefixes (e.g., `01-filesystem`, `02-github`)
2. Implement dependency checking in custom servers
3. Use server initialization hooks (if available)

**Example with prefixes**:
```json
{
  "01-core-filesystem": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-filesystem"]
  },
  "02-github": {
    "command": "docker",
    "args": [...]
  }
}
```

### Performance Optimization

**Minimize Server Count**:
- Only enable servers you actively use
- Disable experimental servers unless testing
- Each server consumes resources (memory, CPU, network)

**Optimize Docker Containers**:
```bash
# Use BuildKit for faster builds
export DOCKER_BUILDKIT=1

# Prune unused resources regularly
docker system prune -a

# Limit container resources
# See Docker Security section
```

**Cache Management**:
```bash
# Clear npx cache if servers are slow to start
rm -rf ~/.npm/_npx

# Clear Docker build cache
docker builder prune

# Clear npm cache
npm cache clean --force
```

**Monitor Performance**:
```bash
# Check Claude Code resource usage
top  # or htop
# Look for node/docker processes

# Monitor Docker container resources
docker stats

# Check network latency
ping api.github.com
curl -w "@curl-format.txt" -o /dev/null -s https://api.github.com/rate_limit
```

**Startup Optimization**:
- Use local registry mirrors (npm, Docker)
- Pre-pull Docker images
- Use persistent environment variables (no reload needed)
- Keep Node.js and Docker updated

---

## Appendix

### Quick Reference

**Configuration File Locations**:
- Linux/WSL: `~/.config/claude/mcp.json`
- macOS: `~/Library/Application Support/Claude/mcp.json`

**Essential Commands**:
```bash
# Validate JSON
jq . ~/.config/claude/mcp.json

# Test environment variable
echo $GITHUB_PERSONAL_ACCESS_TOKEN

# Test Docker
docker ps

# Test Node.js
node --version && npx --version

# Pull Docker image
docker pull ghcr.io/github/github-mcp-server

# Clear npx cache
rm -rf ~/.npm/_npx
```

### Server Comparison Matrix

| Server | Category | Docker | API Key | Use Case |
|--------|----------|--------|---------|----------|
| sequential-thinking | CORE | No | No | Complex reasoning |
| filesystem | CORE | No | No | File operations |
| web-search | OPTIONAL | No | Yes | Research, documentation |
| github | OPTIONAL | Yes | Yes | Repository management |
| context7 | EXPERIMENTAL | No | Maybe | Context management |
| browsertools | EXPERIMENTAL | No | No | Browser automation |
| magic-mcp | EXPERIMENTAL | No | No | Unknown features |

### Recommended Configurations

**Minimal (CORE only)**:
```json
{
  "mcpServers": {
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem"]
    }
  }
}
```

**Developer (CORE + GitHub)**:
```json
{
  "mcpServers": {
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem"]
    },
    "github": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
        "ghcr.io/github/github-mcp-server"
      ]
    }
  }
}
```

**Full (All OPTIONAL)**:
```json
{
  "mcpServers": {
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem"]
    },
    "web-search": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-web-search"]
    },
    "github": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
        "ghcr.io/github/github-mcp-server"
      ]
    }
  }
}
```

### Further Resources

**Official Documentation**:
- MCP Specification: [https://modelcontextprotocol.io](https://modelcontextprotocol.io)
- Claude Code Documentation: [https://docs.anthropic.com/claude-code](https://docs.anthropic.com/claude-code)
- GitHub MCP Server: [https://github.com/github/github-mcp-server](https://github.com/github/github-mcp-server)

**Community Resources**:
- MCP Servers Repository: [https://github.com/modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers)
- MCP SDK: [https://github.com/modelcontextprotocol/sdk](https://github.com/modelcontextprotocol/sdk)

**Related Documentation**:
- Docker Desktop WSL Integration: [https://docs.docker.com/desktop/wsl/](https://docs.docker.com/desktop/wsl/)
- GitHub Personal Access Tokens: [https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
- Node.js Version Management: [https://github.com/nvm-sh/nvm](https://github.com/nvm-sh/nvm)

---

## Change Log

**Version 1.0.0** (2026-01-21):
- Initial comprehensive documentation
- Documented all servers from claude-mcp.example.json
- Added WSL-specific guides
- Included troubleshooting sections
- Added security best practices

---

## Contributing

This documentation should evolve as MCP servers are added, updated, or deprecated.

**When to update**:
- New MCP servers are added to configuration
- Server configurations change
- New troubleshooting patterns are discovered
- Security best practices evolve
- WSL/Docker integration changes

**How to update**:
1. Update relevant sections
2. Test instructions on clean system
3. Add to Change Log
4. Update version number and date
5. Commit with descriptive message

---

**Maintained By**: Development Team
**Last Updated**: 2026-01-21
**Version**: 1.0.0
**License**: MIT (adapt freely for your projects)
