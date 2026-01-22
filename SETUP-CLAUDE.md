# Claude Code Setup Guide

> Complete guide for setting up these dotfiles with Claude Code

**Version**: 1.0.0
**Last Updated**: 2026-01-21
**Audience**: Developers migrating to or setting up Claude Code

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [MCP Server Configuration](#mcp-server-configuration)
4. [Platform-Specific Instructions](#platform-specific-instructions)
5. [Migration from Cursor](#migration-from-cursor)
6. [Verification](#verification)
7. [Troubleshooting](#troubleshooting)
8. [Security Best Practices](#security-best-practices)
9. [Next Steps](#next-steps)

---

## Prerequisites

Before you begin, ensure you have the following installed:

### Required

**Claude Code**
- Download from [Anthropic's official site](https://claude.com/claude-code)
- Latest version recommended

**Node.js (v18 or higher)**
```bash
# Check your version
node --version

# If not installed or version is < 18:
# See platform-specific instructions below
```

**Git**
```bash
# Verify installation
git --version

# If not installed, see platform-specific instructions
```

### Optional (but recommended)

**Docker Desktop** (required for GitHub MCP server)
- Download from [docker.com](https://www.docker.com/products/docker-desktop)
- Needed for GitHub integration via MCP
- WSL users: Enable WSL2 integration in Docker Desktop settings

**GitHub Account** (for GitHub MCP server)
- Personal Access Token with appropriate scopes
- See [MCP Configuration](#github-integration) section

---

## Installation

### Step 1: Clone the Dotfiles Repository

**Choose your clone location carefully:**

#### Linux / macOS
```bash
# Clone to your home directory
cd ~
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles

# Or clone to a projects directory
mkdir -p ~/projects
cd ~/projects
git clone https://github.com/yourusername/dotfiles.git
```

#### WSL (Recommended)
```bash
# IMPORTANT: Clone to WSL filesystem, NOT /mnt/c/
# This provides best performance

cd ~
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles

# Or use a projects directory
mkdir -p ~/projects
cd ~/projects
git clone https://github.com/yourusername/dotfiles.git
```

**Why WSL filesystem matters:**
- **Fast**: Native WSL filesystem (`/home/...`) is ~10x faster than `/mnt/c/...`
- **Reliable**: Git operations work better in native filesystem
- **Secure**: Proper Linux file permissions

**DO NOT** clone to `/mnt/c/Users/...` in WSL - this will be slow.

### Step 2: Install Shell Configuration (Optional)

If you want to use the shell configurations (bash/zsh):

```bash
cd ~/dotfiles

# Backup existing configurations
cp ~/.bashrc ~/.bashrc.backup 2>/dev/null || true
cp ~/.zshrc ~/.zshrc.backup 2>/dev/null || true
cp ~/.gitconfig ~/.gitconfig.backup 2>/dev/null || true

# Create symlinks (Linux/macOS/WSL)
ln -sf ~/dotfiles/.bashrc ~/.bashrc
ln -sf ~/dotfiles/.zshrc ~/.zshrc
ln -sf ~/dotfiles/.gitconfig ~/.gitconfig
ln -sf ~/dotfiles/.bash_profile ~/.bash_profile
ln -sf ~/dotfiles/.profile ~/.profile

# Reload shell
source ~/.bashrc
# or
source ~/.zshrc
```

**What you get:**
- Common shell utilities and aliases
- Git configuration
- SSH agent setup
- Environment variable management

### Step 3: Review the Documentation

Before configuring MCP servers, familiarize yourself with:

```bash
# Main Claude Code guidelines
cat ~/dotfiles/CLAUDE.md

# MCP servers documentation
cat ~/dotfiles/docs/mcp-servers.md

# Workflow examples
cat ~/dotfiles/docs/workflows.md
```

---

## MCP Server Configuration

MCP (Model Context Protocol) servers extend Claude Code's capabilities with additional tools like GitHub integration, web search, and enhanced reasoning.

### Understanding MCP Configuration File Locations

**Linux / WSL:**
```
~/.config/claude/mcp.json
```

**macOS:**
```
~/Library/Application Support/Claude/mcp.json
```

### Step 1: Create Configuration Directory

```bash
# Linux / WSL
mkdir -p ~/.config/claude

# macOS
mkdir -p ~/Library/Application\ Support/Claude
```

### Step 2: Choose Your Configuration Level

We provide an example configuration file with three tiers of MCP servers:

| Tier | Description | Requires |
|------|-------------|----------|
| **CORE** | Essential servers (recommended for all) | Node.js only |
| **OPTIONAL** | Useful for specific workflows | API keys, Docker |
| **EXPERIMENTAL** | Untested, unstable features | Various |

**Recommendation:** Start with CORE servers only, add OPTIONAL as needed.

### Step 3: Copy and Customize Configuration

#### Option A: Minimal Setup (CORE servers only)

```bash
# Linux / WSL
cat > ~/.config/claude/mcp.json << 'EOF'
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
EOF

# macOS
cat > ~/Library/Application\ Support/Claude/mcp.json << 'EOF'
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
EOF
```

This gives you:
- **sequential-thinking**: Enhanced reasoning for complex problems
- **filesystem**: Extended file operations

**No API keys or Docker required** for this configuration.

#### Option B: Full Setup (with GitHub)

If you want GitHub integration:

**Prerequisites:**
1. Docker Desktop installed and running
2. GitHub Personal Access Token (see [GitHub Integration](#github-integration))

```bash
# Linux / WSL
cat > ~/.config/claude/mcp.json << 'EOF'
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
    },
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
}
EOF
```

Then add your GitHub token to your shell environment:

```bash
# Add to ~/.bashrc or ~/.zshrc
echo 'export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_your_token_here"' >> ~/.bashrc

# Reload shell
source ~/.bashrc
```

**Replace `ghp_your_token_here`** with your actual token (see [GitHub Integration](#github-integration)).

#### Option C: Use the Example File

```bash
# Copy the example file
# Linux / WSL
cp ~/dotfiles/claude-mcp.example.json ~/.config/claude/mcp.json

# macOS
cp ~/dotfiles/claude-mcp.example.json ~/Library/Application\ Support/Claude/mcp.json

# IMPORTANT: Remove documentation fields
# The example contains _comment, _description, etc. that must be removed
```

**Remove metadata fields** using this command:

```bash
# Linux / WSL
jq 'walk(if type == "object" then with_entries(select(.key | startswith("_") | not)) else . end)' \
  ~/dotfiles/claude-mcp.example.json > ~/.config/claude/mcp.json

# macOS
jq 'walk(if type == "object" then with_entries(select(.key | startswith("_") | not)) else . end)' \
  ~/dotfiles/claude-mcp.example.json > ~/Library/Application\ Support/Claude/mcp.json
```

### GitHub Integration

To use the GitHub MCP server, you need a Personal Access Token.

**Step 1: Create Token**

1. Go to [https://github.com/settings/tokens](https://github.com/settings/tokens)
2. Click **"Generate new token"** → **"Generate new token (classic)"**
3. Give it a name: `claude-code-mcp`
4. Set expiration: **90 days** (recommended for security)
5. Select scopes:
   - **`repo`** - Full repository access (required)
   - **`read:org`** - Read organization data (recommended)
   - **`read:user`** - Read user profile (recommended)
6. Click **"Generate token"**
7. **Copy the token immediately** (you won't see it again)

**Step 2: Configure Token**

**Option A: Environment Variable (Recommended)**

```bash
# Add to ~/.bashrc or ~/.zshrc
echo 'export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_your_actual_token_here"' >> ~/.bashrc

# Reload shell
source ~/.bashrc

# Verify
echo $GITHUB_PERSONAL_ACCESS_TOKEN
```

**Option B: Direct in mcp.json (Less Secure)**

Only use this if you understand the security implications:

```json
{
  "github": {
    "command": "docker",
    "args": [
      "run",
      "-i",
      "--rm",
      "-e",
      "GITHUB_PERSONAL_ACCESS_TOKEN=ghp_your_actual_token_here",
      "ghcr.io/github/github-mcp-server"
    ]
  }
}
```

**WARNING:** If using Option B, never commit `mcp.json` to git!

**Step 3: Test Token**

```bash
# Verify token works
curl -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
  https://api.github.com/user

# Should return your GitHub user information
```

### Validate Configuration

```bash
# Check JSON syntax
# Linux / WSL
jq . ~/.config/claude/mcp.json

# macOS
jq . ~/Library/Application\ Support/Claude/mcp.json

# Should output formatted JSON without errors
```

### Restart Claude Code

**MCP configuration changes require restarting Claude Code to take effect.**

1. Close Claude Code completely
2. Reopen Claude Code
3. MCP servers will initialize on startup

---

## Platform-Specific Instructions

### Linux

#### Install Node.js (if needed)

**Ubuntu/Debian:**
```bash
# Install from NodeSource repository (recommended)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version
npm --version
```

**Fedora:**
```bash
sudo dnf install nodejs npm
```

**Arch:**
```bash
sudo pacman -S nodejs npm
```

#### Install Docker (if needed)

**Ubuntu/Debian:**
```bash
# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker.io

# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Add user to docker group (avoid using sudo)
sudo usermod -aG docker $USER

# Log out and back in for group changes to take effect
```

**Fedora/CentOS/RHEL:**
```bash
sudo dnf install docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

#### Install Git (if needed)

```bash
# Ubuntu/Debian
sudo apt-get install git

# Fedora
sudo dnf install git

# Arch
sudo pacman -S git
```

---

### macOS

#### Install Node.js (if needed)

**Using Homebrew (recommended):**
```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Node.js
brew install node

# Verify installation
node --version
npm --version
```

**Using nvm (Node Version Manager):**
```bash
# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Reload shell
source ~/.zshrc  # or ~/.bashrc

# Install Node.js 18
nvm install 18
nvm use 18
nvm alias default 18
```

#### Install Docker Desktop

1. Download [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop)
2. Open the downloaded `.dmg` file
3. Drag Docker to Applications folder
4. Open Docker from Applications
5. Wait for Docker to start (whale icon in menu bar)

#### Install Git (if needed)

Git comes pre-installed on macOS (via Xcode Command Line Tools).

If not installed:
```bash
xcode-select --install
```

---

### WSL (Windows Subsystem for Linux)

**This section is critical for WSL users - read carefully.**

#### Prerequisites

**Windows Requirements:**
- Windows 10 version 2004+ or Windows 11
- WSL2 enabled (not WSL1)

**Check WSL version:**
```powershell
# In PowerShell (Windows)
wsl --version
wsl -l -v
```

If not on WSL2, upgrade:
```powershell
# In PowerShell (Administrator)
wsl --set-version Ubuntu 2
```

#### Install Node.js in WSL

**IMPORTANT:** Install Node.js **inside WSL**, not in Windows.

```bash
# In WSL terminal
# Install using NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version  # Should show v18.x.x
npm --version
npx --version
```

**Using nvm (recommended for version management):**
```bash
# Install nvm in WSL
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Reload shell
source ~/.bashrc

# Install Node.js 18
nvm install 18
nvm use 18
nvm alias default 18

# Verify
node --version
```

#### Docker Desktop Integration (Critical for GitHub MCP)

**Step 1: Install Docker Desktop for Windows**

1. Download [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop)
2. Run the installer
3. During installation, ensure **"Use WSL 2 instead of Hyper-V"** is selected
4. Restart Windows if prompted
5. Open Docker Desktop

**Step 2: Enable WSL Integration**

1. Open Docker Desktop
2. Click the gear icon (Settings)
3. Navigate to **Resources → WSL Integration**
4. Enable **"Enable integration with my default WSL distro"**
5. Enable integration for your specific distro (e.g., **Ubuntu**)
6. Click **"Apply & Restart"**

**Step 3: Verify Integration**

```bash
# In WSL terminal
docker --version
# Should show Docker version (e.g., Docker version 24.0.x)

docker ps
# Should connect without errors (may show empty list)

docker run hello-world
# Should download and run test container
```

**Common Issues:**

**"Cannot connect to Docker daemon":**
```bash
# Ensure Docker Desktop is running (check Windows system tray)
# Restart WSL
wsl --shutdown  # In PowerShell
# Open WSL again and retry
```

**"Permission denied":**
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in to WSL
exit
# Open new WSL terminal
```

#### Where to Clone Dotfiles in WSL

**DO THIS:**
```bash
# Clone to WSL native filesystem
cd ~
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles

# Or use projects directory
mkdir -p ~/projects
cd ~/projects
git clone https://github.com/yourusername/dotfiles.git
```

**DO NOT DO THIS:**
```bash
# ❌ BAD: Cloning to Windows filesystem via /mnt/c/
cd /mnt/c/Users/YourName/projects  # SLOW!
git clone https://github.com/yourusername/dotfiles.git
```

**Why?**
- Native WSL filesystem (`/home/...`) is **~10x faster** than `/mnt/c/...`
- Git operations are much faster
- File permissions work correctly
- Better compatibility with Linux tools

**Accessing WSL Files from Windows:**

You can access your WSL files from Windows File Explorer:

```
\\wsl$\Ubuntu\home\yourusername\dotfiles
```

Or from command line:
```bash
# In WSL, convert to Windows path
wslpath -w ~/dotfiles
```

#### Configure Claude Code in WSL

**MCP configuration path in WSL:**
```
~/.config/claude/mcp.json
/home/yourusername/.config/claude/mcp.json
```

**Use Linux paths**, not Windows paths:
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

**NOT:**
```json
{
  "env": {
    "PROJECT_ROOT": "C:\\Users\\Fred\\projects"  // ❌ WRONG
  }
}
```

#### Environment Variables in WSL

Add environment variables to your shell config:

```bash
# Add to ~/.bashrc
cat >> ~/.bashrc << 'EOF'

# Claude Code MCP Environment Variables
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_your_token_here"
export NODE_ENV="development"

EOF

# Reload shell
source ~/.bashrc

# Verify
echo $GITHUB_PERSONAL_ACCESS_TOKEN
```

#### Path Conversion (when needed)

If you need to convert between Windows and WSL paths:

```bash
# Windows path to WSL path
wslpath 'C:\Users\Fred\Documents'
# Output: /mnt/c/Users/Fred/Documents

# WSL path to Windows path
wslpath -w /home/fred/projects
# Output: \\wsl$\Ubuntu\home\fred\projects
```

#### Performance Optimization

**1. Use Native WSL Filesystem**
```bash
# Good: Fast
cd ~/projects
git clone https://github.com/...

# Bad: Slow
cd /mnt/c/Users/Fred/projects
git clone https://github.com/...
```

**2. Configure Windows Defender Exclusions**

Add WSL directories to Windows Defender exclusions:

1. Open Windows Security
2. Go to **Virus & threat protection → Manage settings → Exclusions**
3. Add folder: `\\wsl$\Ubuntu\home\yourusername`

Or via PowerShell (Administrator):
```powershell
Add-MpPreference -ExclusionPath "\\wsl$\Ubuntu\home\yourusername"
```

**3. Optimize WSL Memory**

Create/edit `C:\Users\YourName\.wslconfig`:

```ini
[wsl2]
memory=8GB
processors=4
swap=2GB
localhostForwarding=true
```

Restart WSL:
```powershell
wsl --shutdown
```

**4. Enable Docker BuildKit**
```bash
# Add to ~/.bashrc
echo 'export DOCKER_BUILDKIT=1' >> ~/.bashrc
source ~/.bashrc
```

---

## Migration from Cursor

If you're migrating from Cursor to Claude Code, here's what you need to know.

### Tool Mapping

Cursor and Claude Code use different tools. Here's the mapping:

| Cursor Tool | Claude Code Tool | Notes |
|------------|------------------|-------|
| `list_dir` | `Bash` (ls) or `Glob` | Use `Glob` for pattern matching |
| `file_search` | `Glob` | Pattern-based file finding |
| `grep_search` | `Grep` | Content search with regex |
| `codebase_search` | `Grep` | Use with appropriate patterns |
| `read_file` | `Read` | Direct file reading |
| `write_to_file` | `Write` | File creation/overwriting |
| `apply_diff` | `Edit` | Surgical edits to existing files |

### MCP Configuration Migration

**Cursor's MCP config location:**
```
~/.cursor/mcp.json
```

**Claude Code's MCP config location:**
```
Linux/WSL: ~/.config/claude/mcp.json
macOS: ~/Library/Application Support/Claude/mcp.json
```

**If you have an existing Cursor MCP configuration:**

```bash
# Linux / WSL
# Copy and adapt Cursor config
cp ~/.cursor/mcp.json ~/.config/claude/mcp.json

# Review and adjust paths if needed
vi ~/.config/claude/mcp.json
```

**Note:** MCP configurations should be compatible between Cursor and Claude Code, but verify server commands and paths.

### Rules and Guidelines

**Cursor uses `.cursorrules` files.** Claude Code uses:
- `CLAUDE.md` for development guidelines
- MCP servers for extended capabilities
- Project-specific documentation

**Migrating your workflow:**

1. Review `~/dotfiles/CLAUDE.md` for development patterns
2. Configure MCP servers for extended functionality
3. Place project-specific instructions in project README or docs
4. Use Claude Code's built-in tools (Glob, Grep, Read, Edit, Write) instead of Cursor equivalents

### What's Different

**Tool Paradigm:**
- **Cursor**: More file-operation focused tools
- **Claude Code**: More search and pattern-matching focused tools

**MCP Integration:**
- **Cursor**: MCP servers available
- **Claude Code**: MCP servers with enhanced integration

**Workflow:**
- **Cursor**: More imperative (tell it exactly what to do)
- **Claude Code**: More declarative (describe what you want)

---

## Verification

After setup, verify everything is working:

### 1. Verify Node.js

```bash
node --version
# Should show v18.x.x or higher

npm --version
# Should show a version number

npx --version
# Should show a version number
```

### 2. Verify Docker (if using GitHub MCP)

```bash
docker --version
# Should show Docker version

docker ps
# Should list containers (may be empty)

docker run hello-world
# Should download and run test container
```

### 3. Verify MCP Configuration

```bash
# Linux / WSL
jq . ~/.config/claude/mcp.json

# macOS
jq . ~/Library/Application\ Support/Claude/mcp.json

# Should output valid JSON without errors
```

### 4. Verify Environment Variables

```bash
echo $GITHUB_PERSONAL_ACCESS_TOKEN
# Should show your token (if configured)
```

### 5. Test GitHub Token (if configured)

```bash
curl -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
  https://api.github.com/user

# Should return your GitHub user info
```

### 6. Test Claude Code

1. Open Claude Code
2. Start a new conversation
3. Ask: "Can you search for package.json files in the current directory?"
4. Claude should use the `Glob` tool to find files
5. If you configured GitHub MCP, ask: "What's my GitHub username?"

**Expected Behavior:**
- MCP servers initialize on startup (check logs if available)
- Claude can use Glob, Grep, Read, Write, Edit tools
- GitHub integration works (if configured)

---

## Troubleshooting

### Common Issues

#### "MCP server failed to start"

**Check JSON syntax:**
```bash
# Linux / WSL
jq . ~/.config/claude/mcp.json

# macOS
jq . ~/Library/Application\ Support/Claude/mcp.json
```

**Check Node.js version:**
```bash
node --version
# Should be v18 or higher
```

**Clear npx cache:**
```bash
rm -rf ~/.npm/_npx
```

**Restart Claude Code:**
- Close completely
- Reopen

#### "Docker daemon not running" (WSL)

**Ensure Docker Desktop is running:**
1. Check Windows system tray for Docker icon
2. If not running, start Docker Desktop from Start menu

**Restart WSL:**
```powershell
# In PowerShell
wsl --shutdown
```
Then open WSL again.

**Verify Docker integration:**
```bash
docker ps
# Should connect without errors
```

#### "GitHub authentication failed"

**Verify token is set:**
```bash
echo $GITHUB_PERSONAL_ACCESS_TOKEN
# Should show your token
```

**Test token validity:**
```bash
curl -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
  https://api.github.com/user

# Should return user info, not 401 error
```

**Reload environment:**
```bash
source ~/.bashrc
# or
source ~/.zshrc
```

**Check token on GitHub:**
- Visit [https://github.com/settings/tokens](https://github.com/settings/tokens)
- Verify token exists and has correct scopes

#### "npx command not found"

**Install Node.js and npm:**

See [Platform-Specific Instructions](#platform-specific-instructions) for your OS.

**Verify installation:**
```bash
node --version
npm --version
npx --version
```

#### "Permission denied" (Docker)

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in
exit
# Open new terminal

# Verify
docker ps
```

#### Files/changes not appearing

**WSL users - check filesystem location:**
```bash
pwd
# Should show /home/... NOT /mnt/c/...

# If in /mnt/c/, move to WSL filesystem
cd ~/projects
```

**Check file permissions:**
```bash
ls -la ~/.config/claude/mcp.json
# Should show -rw-r--r-- or -rw-------
```

### WSL-Specific Issues

#### "Cannot access Windows files from WSL"

Windows files are accessible via `/mnt/c/`:
```bash
ls /mnt/c/Users/YourName/Documents
```

But **don't use this for development** - it's slow.

#### "WSL is slow"

**Move projects to WSL filesystem:**
```bash
# Instead of /mnt/c/Users/YourName/projects
# Use /home/yourusername/projects
mkdir -p ~/projects
cd ~/projects
```

**Add Windows Defender exclusions** (see [WSL Performance Optimization](#performance-optimization))

#### "Docker integration broken"

**Re-enable WSL integration in Docker Desktop:**
1. Open Docker Desktop (Windows)
2. Settings → Resources → WSL Integration
3. Enable integration for your distro
4. Apply & Restart

**Restart WSL:**
```powershell
wsl --shutdown
```

### Getting More Help

**Documentation:**
- `~/dotfiles/CLAUDE.md` - Development guidelines
- `~/dotfiles/docs/mcp-servers.md` - MCP server details
- `~/dotfiles/docs/workflows.md` - Workflow examples

**Official Resources:**
- [Claude Code Documentation](https://docs.anthropic.com/claude-code)
- [MCP Specification](https://modelcontextprotocol.io)
- [Docker WSL Integration](https://docs.docker.com/desktop/wsl/)

**Community:**
- GitHub Issues on this repository
- Claude Code community forums

---

## Security Best Practices

### API Keys and Tokens

**DO:**
- ✅ Use environment variables for API keys
- ✅ Set token expiration (90 days recommended)
- ✅ Use minimal required scopes
- ✅ Rotate tokens regularly
- ✅ Restrict file permissions: `chmod 600 ~/.config/claude/mcp.json`

**DON'T:**
- ❌ Commit API keys to git
- ❌ Share tokens in screenshots/logs
- ❌ Use production tokens for testing
- ❌ Store tokens in cloud storage unencrypted

### File Permissions

```bash
# MCP config should be user-readable only
chmod 600 ~/.config/claude/mcp.json

# Verify
ls -la ~/.config/claude/mcp.json
# Should show: -rw------- (600)
```

### Git Configuration

```bash
# Add to .gitignore to prevent accidental commits
cat >> ~/.gitignore_global << 'EOF'
# Claude Code / MCP
.config/claude/mcp.json
.env
.env.*

# Credentials
**/secrets.*
**/credentials.*
EOF

# Configure global gitignore
git config --global core.excludesfile ~/.gitignore_global
```

### Docker Security

**Use minimal container permissions:**
```json
{
  "github": {
    "command": "docker",
    "args": [
      "run",
      "-i",
      "--rm",
      "--read-only",
      "--security-opt=no-new-privileges",
      "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
      "ghcr.io/github/github-mcp-server"
    ]
  }
}
```

**Keep Docker images updated:**
```bash
# Pull latest images regularly
docker pull ghcr.io/github/github-mcp-server
```

### Audit Security

**Check for accidentally committed secrets:**
```bash
git log -p | grep -E "ghp_|sk_|token|api.?key" -i
```

**Review token usage:**
- GitHub: [https://github.com/settings/tokens](https://github.com/settings/tokens)
- Check "Last used" timestamp

**Monitor API rate limits:**
```bash
curl -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
  https://api.github.com/rate_limit
```

---

## Next Steps

Congratulations! You've set up Claude Code with these dotfiles.

### Learn the Workflow

**Read the documentation:**

1. **Development Guidelines** (`CLAUDE.md`)
   - How to write quality code with Claude Code
   - Testing strategies
   - Git workflow
   - Language-specific best practices

2. **MCP Servers** (`docs/mcp-servers.md`)
   - Detailed documentation for each MCP server
   - Configuration options
   - Troubleshooting guides

3. **Workflows** (`docs/workflows.md`)
   - Common development workflows
   - Example conversations with Claude Code
   - Pattern library

### Start Using Claude Code

**Try these tasks:**

1. **Explore your codebase:**
   ```
   "Show me all TypeScript files in this project"
   "Find all TODO comments in the codebase"
   "What's the structure of the src directory?"
   ```

2. **Code analysis:**
   ```
   "Review the authentication logic in src/auth/"
   "Find unused imports across the project"
   "Check for security vulnerabilities in API endpoints"
   ```

3. **Make changes:**
   ```
   "Add error handling to the fetchUserData function"
   "Create a new React component for user profile"
   "Write tests for the validation utilities"
   ```

4. **GitHub operations** (if configured):
   ```
   "Create an issue for the login bug we discussed"
   "Search for open issues related to authentication"
   "Create a pull request from this feature branch"
   ```

### Customize for Your Workflow

**Add project-specific instructions:**

Create a `.claude-project.md` file in your project root:

```markdown
# Project: MyApp

## Stack
- React + TypeScript
- Node.js backend
- PostgreSQL database
- Deployed on Vercel

## Conventions
- Use functional components with hooks
- All API calls in src/api/
- Tests colocated with source files
- Prefer small, focused commits

## Important
- Never modify legacy/ directory
- All database changes need migration
- Run npm test before committing
```

**Configure additional MCP servers:**

See `docs/mcp-servers.md` for available servers and configuration.

**Explore advanced features:**

- Custom MCP servers for your specific needs
- Integration with your CI/CD pipeline
- Team-wide configuration standards

### Share with Your Team

If this setup works well for you:

1. Fork this repository
2. Customize for your team's needs
3. Document team-specific conventions
4. Share the setup guide

### Stay Updated

**Keep dependencies updated:**
```bash
# Update Node.js (via nvm)
nvm install --lts
nvm use --lts

# Update Docker images
docker pull ghcr.io/github/github-mcp-server
```

**Monitor for changes:**
- Star this repository for updates
- Watch Claude Code release notes
- Follow MCP specification updates

---

## Quick Reference

### File Locations

**Dotfiles:**
```
~/dotfiles/                          # This repository
~/dotfiles/CLAUDE.md                 # Development guidelines
~/dotfiles/docs/mcp-servers.md       # MCP documentation
~/dotfiles/claude-mcp.example.json   # Example MCP config
```

**Claude Code MCP Config:**
```
Linux/WSL: ~/.config/claude/mcp.json
macOS:     ~/Library/Application Support/Claude/mcp.json
```

### Essential Commands

```bash
# Validate MCP config
jq . ~/.config/claude/mcp.json

# Test environment variable
echo $GITHUB_PERSONAL_ACCESS_TOKEN

# Test Docker
docker ps

# Test Node.js
node --version

# Restart Claude Code
# Close and reopen the application

# Clear npx cache
rm -rf ~/.npm/_npx

# Pull Docker images
docker pull ghcr.io/github/github-mcp-server
```

### WSL Quick Reference

```bash
# Check WSL version
wsl --version
wsl -l -v

# Restart WSL
wsl --shutdown

# Convert paths
wslpath 'C:\Users\Fred\Documents'
wslpath -w /home/fred/projects

# Access WSL from Windows
\\wsl$\Ubuntu\home\yourusername

# Check Docker integration
docker ps
```

---

## Support

**Issues with setup?**
1. Check [Troubleshooting](#troubleshooting) section
2. Review [MCP Servers documentation](docs/mcp-servers.md)
3. Open an issue on this repository

**Want to contribute?**
1. Fork this repository
2. Make improvements
3. Submit a pull request

**Feedback?**
- Share your experience
- Suggest improvements
- Report issues

---

**Last Updated**: 2026-01-21
**Version**: 1.0.0
**Maintained By**: Development Team
**License**: MIT

**Happy Coding with Claude!**
