# Tool Mapping Guide: Cursor to Claude Code

## Introduction

This guide is designed for developers transitioning from Cursor to Claude Code. While both tools offer AI-powered code assistance, they use different underlying tool systems. This document provides a comprehensive mapping between Cursor's tools and Claude Code's equivalents, along with practical examples and best practices.

Claude Code is Anthropic's official CLI for Claude, optimized for terminal-based workflows with powerful search, file manipulation, and command execution capabilities. Understanding the tool differences will help you work more efficiently and leverage Claude Code's strengths.

---

## Quick Reference: Tool Mapping Table

| Cursor Tool | Claude Code Tool(s) | Primary Use Case | Notes |
|-------------|---------------------|------------------|-------|
| `list_dir` | `Glob` + `Bash ls` | Directory listing, file discovery | Glob for patterns, Bash for detailed listings |
| `file_search` | `Glob` | Finding files by name/pattern | Fast pattern matching with glob syntax |
| `grep_search` | `Grep` | Searching file contents | Built on ripgrep, supports regex |
| `codebase_search` | `Grep` | Multi-file content search | Use with glob patterns for filtering |
| `read_file` | `Read` | Reading file contents | Supports images, PDFs, Jupyter notebooks |
| `write_to_file` | `Write` | Creating/overwriting files | Requires prior Read for existing files |
| `edit_file` | `Edit` | Modifying existing files | Exact string replacement |
| `execute_command` | `Bash` | Running shell commands | Persistent working directory |

---

## Detailed Tool Comparisons

### 1. Directory Listing: `list_dir` → `Glob` / `Bash ls`

#### Cursor (list_dir)
```
list_dir(path="/home/fred/projects/myapp")
```

#### Claude Code - Option A: Glob (Pattern-based)
```
Glob(pattern="*", path="/home/fred/projects/myapp")
Glob(pattern="**/*.js", path="/home/fred/projects/myapp")
```

#### Claude Code - Option B: Bash ls (Detailed listing)
```
Bash(command="ls -la /home/fred/projects/myapp")
Bash(command="ls -R /home/fred/projects/myapp")
```

**When to use which:**
- **Glob**: When you need to find files matching specific patterns (e.g., all `.js` files)
- **Bash ls**: When you need detailed file information (permissions, sizes, timestamps)

**Examples:**

```bash
# List all TypeScript files recursively
Glob(pattern="**/*.ts")

# List all config files in root
Glob(pattern="*.config.{js,ts,json}")

# Detailed listing with sizes and permissions
Bash(command="ls -lh /home/fred/projects/myapp")

# Tree-like directory structure
Bash(command="tree -L 2 /home/fred/projects/myapp")
```

---

### 2. File Search: `file_search` → `Glob`

#### Cursor (file_search)
```
file_search(query="config", path="/home/fred/projects")
```

#### Claude Code (Glob)
```
Glob(pattern="**/*config*")
Glob(pattern="**/*.config.{js,ts,json}")
Glob(pattern="**/config/**")
```

**Advantages in Claude Code:**
- Precise glob pattern matching
- Faster performance on large codebases
- Multiple patterns can be run in parallel

**Common Patterns:**

```bash
# Find all test files
Glob(pattern="**/*.test.{js,ts,tsx}")
Glob(pattern="**/__tests__/**/*.{js,ts}")

# Find component files
Glob(pattern="**/components/**/*.tsx")

# Find configuration files
Glob(pattern="**/{.config,config}/**")
Glob(pattern="**/.{eslintrc,prettierrc}*")

# Find files by exact name
Glob(pattern="**/package.json")
Glob(pattern="**/README.md")
```

---

### 3. Content Search: `grep_search` / `codebase_search` → `Grep`

#### Cursor (grep_search / codebase_search)
```
grep_search(pattern="function calculateTotal", path="/home/fred/projects")
codebase_search(query="TODO:", file_pattern="*.js")
```

#### Claude Code (Grep)
```
Grep(
  pattern="function calculateTotal",
  path="/home/fred/projects",
  output_mode="content"
)

Grep(
  pattern="TODO:",
  glob="*.js",
  output_mode="content"
)
```

**Key Parameters:**
- `pattern`: Regex pattern (ripgrep syntax)
- `glob`: File filter (e.g., `"*.js"`, `"**/*.{ts,tsx}"`)
- `type`: File type filter (e.g., `"js"`, `"py"`, `"rust"`)
- `output_mode`: `"content"` (show lines), `"files_with_matches"` (show files), `"count"` (show counts)
- `-i`: Case insensitive
- `-A`, `-B`, `-C`: Context lines (after, before, both)

**Practical Examples:**

```bash
# Find all TODO comments in JavaScript files
Grep(
  pattern="TODO:",
  type="js",
  output_mode="content"
)

# Find function definitions (case insensitive)
Grep(
  pattern="function\\s+\\w+",
  glob="**/*.js",
  output_mode="content",
  -i=true
)

# Find imports with context
Grep(
  pattern="import.*from.*react",
  type="js",
  output_mode="content",
  -A=2,
  -B=1
)

# Find all files containing a specific class
Grep(
  pattern="class UserController",
  output_mode="files_with_matches"
)

# Count occurrences across files
Grep(
  pattern="console\\.log",
  type="js",
  output_mode="count"
)

# Multiline search (patterns spanning multiple lines)
Grep(
  pattern="interface\\s+User\\s*\\{[\\s\\S]*?email",
  multiline=true,
  type="ts"
)
```

**Performance Tips:**
- Use `type` parameter for better performance than `glob`
- Use `files_with_matches` when you only need file paths
- Limit search scope with `path` parameter
- Use `head_limit` to limit results

---

### 4. Reading Files: `read_file` → `Read`

#### Cursor (read_file)
```
read_file(path="/home/fred/projects/myapp/src/index.js")
```

#### Claude Code (Read)
```
Read(file_path="/home/fred/projects/myapp/src/index.js")
```

**Enhanced Capabilities in Claude Code:**
- Supports images (PNG, JPG, etc.) - returns visual content
- Supports PDFs - extracts text and visual content
- Supports Jupyter notebooks (.ipynb) - shows all cells with outputs
- Line-based reading with `offset` and `limit` for large files

**Advanced Examples:**

```bash
# Read entire file
Read(file_path="/home/fred/projects/myapp/src/index.js")

# Read specific section of large file (lines 100-200)
Read(
  file_path="/home/fred/projects/myapp/src/index.js",
  offset=100,
  limit=100
)

# Read image file (shows visual content)
Read(file_path="/home/fred/screenshots/ui-mockup.png")

# Read PDF
Read(file_path="/home/fred/docs/specification.pdf")

# Read Jupyter notebook
Read(file_path="/home/fred/analysis/data-exploration.ipynb")
```

**Parallel Reading:**
```bash
# Read multiple related files in parallel
Read(file_path="/home/fred/myapp/package.json")
Read(file_path="/home/fred/myapp/tsconfig.json")
Read(file_path="/home/fred/myapp/README.md")
```

---

### 5. Writing Files: `write_to_file` → `Write`

#### Cursor (write_to_file)
```
write_to_file(
  path="/home/fred/projects/myapp/config.json",
  content='{"key": "value"}'
)
```

#### Claude Code (Write)
```
Write(
  file_path="/home/fred/projects/myapp/config.json",
  content='{"key": "value"}'
)
```

**Important Constraints:**
- **MUST** use `Read` first before writing to existing files
- Overwrites the entire file
- Prefer `Edit` for modifying existing files
- Avoid creating files unless necessary

**Proper Usage Pattern:**

```bash
# CORRECT: Read before writing to existing file
Read(file_path="/home/fred/myapp/config.json")
# ... then after analyzing ...
Write(
  file_path="/home/fred/myapp/config.json",
  content='{"key": "updated value"}'
)

# CORRECT: Writing new file (no Read needed)
Write(
  file_path="/home/fred/myapp/new-feature.js",
  content='export function newFeature() { ... }'
)
```

**Anti-pattern:**
```bash
# WRONG: Writing to existing file without reading first
Write(file_path="/home/fred/myapp/existing-file.js", content="...")
# This will fail!
```

---

### 6. Editing Files: `edit_file` → `Edit`

#### Cursor (edit_file)
```
edit_file(
  path="/home/fred/myapp/index.js",
  old_text="const port = 3000",
  new_text="const port = 8080"
)
```

#### Claude Code (Edit)
```
Edit(
  file_path="/home/fred/myapp/index.js",
  old_string="const port = 3000",
  new_string="const port = 8080"
)
```

**Critical Requirements:**
- **MUST** use `Read` before editing
- `old_string` must be EXACT (including whitespace, indentation)
- `old_string` must be UNIQUE unless using `replace_all=true`
- Preserve exact indentation from source file

**Advanced Usage:**

```bash
# Single replacement (old_string must be unique)
Edit(
  file_path="/home/fred/myapp/index.js",
  old_string="const port = 3000;",
  new_string="const port = process.env.PORT || 8080;"
)

# Replace all occurrences (renaming variable)
Edit(
  file_path="/home/fred/myapp/index.js",
  old_string="getUserData",
  new_string="fetchUserData",
  replace_all=true
)

# Multi-line replacement (preserve indentation)
Edit(
  file_path="/home/fred/myapp/server.js",
  old_string="app.get('/users', (req, res) => {
  res.json(users);
});",
  new_string="app.get('/users', async (req, res) => {
  const users = await db.getUsers();
  res.json(users);
});"
)
```

**Common Pitfalls:**

```bash
# WRONG: Not enough context (multiple matches)
Edit(
  file_path="/home/fred/myapp/index.js",
  old_string="const port",  # Too vague!
  new_string="const PORT"
)

# CORRECT: Include enough context for uniqueness
Edit(
  file_path="/home/fred/myapp/index.js",
  old_string="const port = 3000;\nconst host = 'localhost';",
  new_string="const PORT = 8080;\nconst host = 'localhost';"
)
```

---

### 7. Command Execution: `execute_command` → `Bash`

#### Cursor (execute_command)
```
execute_command(command="npm test")
```

#### Claude Code (Bash)
```
Bash(
  command="npm test",
  description="Run test suite"
)
```

**Key Features:**
- Working directory persists between commands
- Shell state does NOT persist (use `&&` for dependent commands)
- Supports timeout (up to 600000ms / 10 minutes)
- Can run commands in background

**Important Guidelines:**
- Always use `description` for clarity
- Quote paths with spaces: `cd "/path with spaces"`
- Chain dependent commands with `&&`
- Use `;` only if you don't care about failures
- Prefer absolute paths over `cd`

**Examples:**

```bash
# Simple command
Bash(
  command="npm install",
  description="Install dependencies"
)

# Chained commands (dependencies)
Bash(
  command="npm run build && npm test",
  description="Build and test application"
)

# Command with quoted paths
Bash(
  command='cd "/home/fred/My Projects" && ls -la',
  description="List contents of directory with spaces"
)

# Long-running command with timeout
Bash(
  command="npm run build",
  description="Build production bundle",
  timeout=300000  # 5 minutes
)

# Background command
Bash(
  command="npm run dev",
  description="Start development server",
  run_in_background=true
)

# Multiple independent commands in parallel
Bash(command="git status", description="Check git status")
Bash(command="npm list", description="List installed packages")
Bash(command="df -h", description="Check disk space")
```

**Prefer Absolute Paths:**

```bash
# GOOD: Using absolute paths
Bash(command="pytest /home/fred/myapp/tests")

# AVOID: Using cd
Bash(command="cd /home/fred/myapp && pytest tests")
```

**Git Operations:**

```bash
# Check status and diff in parallel
Bash(command="git status", description="Check working tree status")
Bash(command="git diff", description="Show unstaged changes")

# Sequential git operations
Bash(
  command="git add src/ && git commit -m 'Update source files'",
  description="Stage and commit changes"
)

# NEVER skip hooks or force push to main without explicit user request
```

---

## Best Practices for Claude Code Tools

### 1. Read Before Write/Edit
Always read a file before modifying it:
```bash
# CORRECT
Read(file_path="/home/fred/myapp/config.js")
# ... analyze ...
Edit(file_path="/home/fred/myapp/config.js", ...)

# WRONG
Edit(file_path="/home/fred/myapp/config.js", ...)  # Will fail!
```

### 2. Parallel Tool Calls
When operations are independent, run them in parallel:
```bash
# Good: Read multiple files at once
Read(file_path="/home/fred/myapp/package.json")
Read(file_path="/home/fred/myapp/tsconfig.json")
Read(file_path="/home/fred/myapp/.eslintrc.js")

# Good: Multiple independent searches
Grep(pattern="TODO", type="js", output_mode="files_with_matches")
Grep(pattern="FIXME", type="js", output_mode="files_with_matches")
Grep(pattern="HACK", type="js", output_mode="files_with_matches")
```

### 3. Use Specialized Tools Over Bash
```bash
# WRONG: Using Bash for tasks with dedicated tools
Bash(command="find . -name '*.js'")  # Use Glob instead
Bash(command="grep -r 'pattern' .")  # Use Grep instead
Bash(command="cat /home/fred/file.js")  # Use Read instead

# CORRECT: Use dedicated tools
Glob(pattern="**/*.js")
Grep(pattern="pattern", output_mode="content")
Read(file_path="/home/fred/file.js")
```

### 4. Precise Glob Patterns
```bash
# Vague
Glob(pattern="**/*test*")

# Precise
Glob(pattern="**/*.{test,spec}.{js,ts,tsx}")
Glob(pattern="**/__tests__/**/*.{js,ts}")
```

### 5. Efficient Grep Usage
```bash
# Use 'type' for performance
Grep(pattern="export", type="js")  # Faster

# Use 'glob' for complex patterns
Grep(pattern="export", glob="**/*.{js,ts}")

# Use appropriate output_mode
Grep(pattern="import", output_mode="files_with_matches")  # Just file paths
Grep(pattern="import", output_mode="content")  # Show matching lines
Grep(pattern="import", output_mode="count")  # Count per file
```

---

## Common Patterns

### Pattern 1: Find and Replace Across Multiple Files

**Cursor approach:**
```
1. codebase_search(query="oldFunctionName")
2. For each file: edit_file(...)
```

**Claude Code approach:**
```bash
# Step 1: Find all files with the pattern
Grep(
  pattern="oldFunctionName",
  type="js",
  output_mode="files_with_matches"
)

# Step 2: Read each file
Read(file_path="/home/fred/myapp/src/file1.js")
Read(file_path="/home/fred/myapp/src/file2.js")

# Step 3: Edit each file
Edit(
  file_path="/home/fred/myapp/src/file1.js",
  old_string="oldFunctionName",
  new_string="newFunctionName",
  replace_all=true
)
Edit(
  file_path="/home/fred/myapp/src/file2.js",
  old_string="oldFunctionName",
  new_string="newFunctionName",
  replace_all=true
)
```

### Pattern 2: Explore Codebase Structure

**Cursor approach:**
```
1. list_dir(path="/home/fred/myapp")
2. list_dir(path="/home/fred/myapp/src")
3. file_search(query="*.js")
```

**Claude Code approach:**
```bash
# Parallel exploration
Glob(pattern="*", path="/home/fred/myapp")
Glob(pattern="src/**/*", path="/home/fred/myapp")
Glob(pattern="**/*.js", path="/home/fred/myapp")

# Or use tree for overview
Bash(
  command="tree -L 3 /home/fred/myapp",
  description="Show directory structure"
)
```

### Pattern 3: Analyze Test Coverage

**Cursor approach:**
```
1. file_search(query="test")
2. For each file: read_file(...)
3. grep_search(pattern="describe|it")
```

**Claude Code approach:**
```bash
# Find all test files
Glob(pattern="**/*.{test,spec}.{js,ts,tsx}")

# Find test patterns
Grep(
  pattern="(describe|it|test)\\(",
  type="js",
  output_mode="count"
)

# Read specific test files in parallel
Read(file_path="/home/fred/myapp/src/__tests__/user.test.js")
Read(file_path="/home/fred/myapp/src/__tests__/auth.test.js")
```

### Pattern 4: Configuration Audit

**Cursor approach:**
```
1. file_search(query="config")
2. For each: read_file(...)
```

**Claude Code approach:**
```bash
# Find all config files
Glob(pattern="**/*.config.{js,ts,json}")
Glob(pattern="**/{.eslintrc,.prettierrc}*")
Glob(pattern="**/config/**")

# Search for specific config values
Grep(
  pattern="apiKey|secret|password",
  glob="**/*.config.{js,json}",
  output_mode="content",
  -i=true
)
```

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Using Bash for File Operations
```bash
# WRONG
Bash(command="cat /home/fred/myapp/index.js")
Bash(command="grep -r 'TODO' /home/fred/myapp")
Bash(command="find /home/fred/myapp -name '*.js'")

# CORRECT
Read(file_path="/home/fred/myapp/index.js")
Grep(pattern="TODO", path="/home/fred/myapp", output_mode="content")
Glob(pattern="**/*.js", path="/home/fred/myapp")
```

### Anti-Pattern 2: Not Reading Before Editing
```bash
# WRONG
Edit(file_path="/home/fred/myapp/index.js", ...)

# CORRECT
Read(file_path="/home/fred/myapp/index.js")
Edit(file_path="/home/fred/myapp/index.js", ...)
```

### Anti-Pattern 3: Sequential Instead of Parallel
```bash
# WRONG: Sequential when operations are independent
Read(file_path="/home/fred/myapp/file1.js")
# wait...
Read(file_path="/home/fred/myapp/file2.js")
# wait...
Read(file_path="/home/fred/myapp/file3.js")

# CORRECT: Parallel
Read(file_path="/home/fred/myapp/file1.js")
Read(file_path="/home/fred/myapp/file2.js")
Read(file_path="/home/fred/myapp/file3.js")
```

### Anti-Pattern 4: Vague Search Patterns
```bash
# WRONG: Too broad
Grep(pattern="user")
Glob(pattern="**/*")

# CORRECT: Specific
Grep(pattern="class User\\b", type="js")
Glob(pattern="**/*.component.tsx")
```

### Anti-Pattern 5: Creating Unnecessary Files
```bash
# WRONG: Creating documentation unprompted
Write(file_path="/home/fred/myapp/README.md", content="...")

# CORRECT: Only create when explicitly requested or necessary
# Prefer editing existing files over creating new ones
```

---

## WSL-Specific Path Handling

When working in WSL (Windows Subsystem for Linux), understanding path conventions is crucial.

### Linux Paths vs Windows Paths

```bash
# Linux path (WSL native)
/home/fred/projects/myapp

# Windows path mounted in WSL
/mnt/c/Users/Fred/Projects/myapp

# Windows path (native - DON'T use in Claude Code)
C:\Users\Fred\Projects\myapp
```

### Best Practices for WSL

1. **Always use absolute Linux-style paths:**
   ```bash
   # CORRECT
   Read(file_path="/home/fred/projects/myapp/index.js")
   Read(file_path="/mnt/c/Users/Fred/Documents/notes.txt")

   # WRONG
   Read(file_path="C:\\Users\\Fred\\Documents\\notes.txt")
   ```

2. **Working with Windows drives:**
   ```bash
   # Windows C: drive
   /mnt/c/path/to/file

   # Windows D: drive
   /mnt/d/path/to/file
   ```

3. **Handling spaces in paths:**
   ```bash
   # Use quotes
   Bash(command='ls "/mnt/c/Program Files"')
   Read(file_path="/mnt/c/Users/Fred/My Documents/file.txt")
   ```

4. **File system performance:**
   ```bash
   # FASTER: Operations on WSL filesystem
   /home/fred/projects/myapp

   # SLOWER: Operations on mounted Windows filesystem
   /mnt/c/Users/Fred/Projects/myapp

   # Tip: Keep frequently accessed projects in WSL for better performance
   ```

5. **Mixed path scenarios:**
   ```bash
   # Search both WSL and Windows locations
   Grep(pattern="TODO", path="/home/fred/projects", output_mode="count")
   Grep(pattern="TODO", path="/mnt/c/Projects", output_mode="count")
   ```

### Common WSL Path Patterns

```bash
# Home directory
/home/fred

# Windows user directory
/mnt/c/Users/Fred

# Common project locations
/home/fred/projects
/mnt/c/Users/Fred/Projects
/mnt/c/dev

# Dotfiles (usually in WSL home)
/home/fred/.bashrc
/home/fred/.config
```

---

## Performance Considerations

### 1. Search Performance

**Fast:**
```bash
# Using type parameter (fastest)
Grep(pattern="export", type="js")

# Using specific glob pattern
Grep(pattern="export", glob="src/**/*.js")

# Limiting scope
Grep(pattern="export", path="/home/fred/myapp/src")
```

**Slow:**
```bash
# No file filtering (searches everything)
Grep(pattern="export")

# Overly broad path
Grep(pattern="export", path="/home/fred")
```

### 2. Parallel Operations

**Efficient:**
```bash
# Parallel reads (execute simultaneously)
Read(file_path="/home/fred/myapp/file1.js")
Read(file_path="/home/fred/myapp/file2.js")
Read(file_path="/home/fred/myapp/file3.js")

# Parallel searches
Grep(pattern="TODO", type="js", output_mode="files_with_matches")
Grep(pattern="FIXME", type="js", output_mode="files_with_matches")
```

**Inefficient:**
```bash
# Sequential when could be parallel
Read(file_path="/home/fred/myapp/file1.js")
# ... wait for response ...
Read(file_path="/home/fred/myapp/file2.js")
# ... wait for response ...
```

### 3. Output Mode Selection

```bash
# Fast: Only need file paths
Grep(pattern="import React", output_mode="files_with_matches")

# Medium: Need to see matches
Grep(pattern="import React", output_mode="content")

# Fast: Just count
Grep(pattern="import React", output_mode="count")
```

### 4. Large File Handling

```bash
# Read entire file (small to medium files)
Read(file_path="/home/fred/myapp/index.js")

# Read in chunks (large files)
Read(file_path="/home/fred/myapp/large.log", offset=0, limit=100)
Read(file_path="/home/fred/myapp/large.log", offset=100, limit=100)

# Use Bash for very large files
Bash(command="head -n 100 /home/fred/myapp/large.log")
Bash(command="tail -n 100 /home/fred/myapp/large.log")
```

### 5. Working Directory Persistence

```bash
# GOOD: Absolute paths (no cd needed)
Bash(command="npm test", description="Run tests from /home/fred/myapp")

# ACCEPTABLE: cd for complex commands
Bash(
  command="cd /home/fred/myapp && npm run build && npm test",
  description="Build and test from project directory"
)

# Note: Working directory persists between Bash calls
Bash(command="cd /home/fred/myapp", description="Change to project directory")
Bash(command="pwd", description="Verify current directory")
# Now in /home/fred/myapp
```

---

## Complex Multi-Tool Workflows

### Workflow 1: Add Feature with Testing

**Scenario:** Add a new authentication feature, write tests, and verify

```bash
# Step 1: Explore existing auth structure
Glob(pattern="**/auth/**/*.{js,ts}")
Grep(pattern="class.*Auth|function.*auth", type="js", output_mode="content")

# Step 2: Read existing auth files (parallel)
Read(file_path="/home/fred/myapp/src/auth/AuthService.js")
Read(file_path="/home/fred/myapp/src/auth/middleware.js")

# Step 3: Create new feature file
Write(
  file_path="/home/fred/myapp/src/auth/TwoFactorAuth.js",
  content="export class TwoFactorAuth { ... }"
)

# Step 4: Update main auth service
Edit(
  file_path="/home/fred/myapp/src/auth/AuthService.js",
  old_string="import { validatePassword } from './utils';",
  new_string="import { validatePassword } from './utils';\nimport { TwoFactorAuth } from './TwoFactorAuth';"
)

# Step 5: Create test file
Write(
  file_path="/home/fred/myapp/src/auth/__tests__/TwoFactorAuth.test.js",
  content="describe('TwoFactorAuth', () => { ... })"
)

# Step 6: Run tests
Bash(
  command="npm test -- TwoFactorAuth.test.js",
  description="Run two-factor auth tests"
)

# Step 7: Verify integration
Bash(
  command="npm run build && npm run lint",
  description="Build and lint to verify integration"
)
```

### Workflow 2: Refactor Codebase

**Scenario:** Rename a function across multiple files

```bash
# Step 1: Find all usages
Grep(
  pattern="getUserData",
  type="js",
  output_mode="files_with_matches"
)

# Step 2: Review usage context
Grep(
  pattern="getUserData",
  type="js",
  output_mode="content",
  -C=3
)

# Step 3: Read all affected files (parallel)
Read(file_path="/home/fred/myapp/src/services/UserService.js")
Read(file_path="/home/fred/myapp/src/components/UserProfile.js")
Read(file_path="/home/fred/myapp/src/api/users.js")

# Step 4: Rename in each file
Edit(
  file_path="/home/fred/myapp/src/services/UserService.js",
  old_string="getUserData",
  new_string="fetchUserData",
  replace_all=true
)
Edit(
  file_path="/home/fred/myapp/src/components/UserProfile.js",
  old_string="getUserData",
  new_string="fetchUserData",
  replace_all=true
)
Edit(
  file_path="/home/fred/myapp/src/api/users.js",
  old_string="getUserData",
  new_string="fetchUserData",
  replace_all=true
)

# Step 5: Verify no remaining references
Grep(
  pattern="getUserData",
  type="js",
  output_mode="files_with_matches"
)

# Step 6: Run tests
Bash(
  command="npm test",
  description="Run full test suite after refactoring"
)
```

### Workflow 3: Debug Production Issue

**Scenario:** Investigate error logs and trace through code

```bash
# Step 1: Find error logs
Grep(
  pattern="ERROR|Exception|Failed",
  glob="**/*.log",
  output_mode="content",
  -i=true,
  head_limit=50
)

# Step 2: Search for error handling in code
Grep(
  pattern="catch|throw new Error",
  type="js",
  output_mode="content",
  -C=5
)

# Step 3: Read relevant error handling code
Read(file_path="/home/fred/myapp/src/api/errorHandler.js")
Read(file_path="/home/fred/myapp/src/services/PaymentService.js")

# Step 4: Check recent changes
Bash(
  command="git log --oneline --since='1 week ago' -- src/services/PaymentService.js",
  description="Check recent commits to PaymentService"
)

# Step 5: Review specific commit
Bash(
  command="git show abc123:src/services/PaymentService.js",
  description="View PaymentService at specific commit"
)

# Step 6: Add enhanced error logging
Edit(
  file_path="/home/fred/myapp/src/services/PaymentService.js",
  old_string="} catch (error) {\n  throw error;\n}",
  new_string="} catch (error) {\n  logger.error('Payment processing failed', { error, context: this.context });\n  throw error;\n}"
)

# Step 7: Test fix locally
Bash(
  command="npm run dev",
  description="Start dev server to test fix",
  run_in_background=true
)
```

### Workflow 4: Dependency Upgrade

**Scenario:** Upgrade React and fix breaking changes

```bash
# Step 1: Check current version
Read(file_path="/home/fred/myapp/package.json")

# Step 2: Find React usage patterns
Grep(
  pattern="import.*from ['\"](react|react-dom)['\"]",
  type="js",
  output_mode="files_with_matches"
)

# Step 3: Check for deprecated APIs
Grep(
  pattern="componentWillMount|componentWillReceiveProps|UNSAFE_",
  type="js",
  output_mode="content"
)

# Step 4: Update package.json
Edit(
  file_path="/home/fred/myapp/package.json",
  old_string='"react": "^17.0.2"',
  new_string='"react": "^18.2.0"'
)
Edit(
  file_path="/home/fred/myapp/package.json",
  old_string='"react-dom": "^17.0.2"',
  new_string='"react-dom": "^18.2.0"'
)

# Step 5: Install new versions
Bash(
  command="npm install",
  description="Install updated React versions",
  timeout=300000
)

# Step 6: Update deprecated patterns (if found)
Read(file_path="/home/fred/myapp/src/components/LegacyComponent.js")
Edit(
  file_path="/home/fred/myapp/src/components/LegacyComponent.js",
  old_string="componentWillMount() {",
  new_string="componentDidMount() {"
)

# Step 7: Run tests
Bash(
  command="npm test",
  description="Run tests after React upgrade"
)

# Step 8: Check build
Bash(
  command="npm run build",
  description="Build production bundle",
  timeout=300000
)
```

### Workflow 5: Security Audit

**Scenario:** Scan for security issues and secrets

```bash
# Step 1: Find potential secrets in code
Grep(
  pattern="(api_?key|secret|password|token|auth)\\s*[=:]\\s*['\"][^'\"]+['\"]",
  output_mode="content",
  -i=true
)

# Step 2: Check for hardcoded credentials
Grep(
  pattern="mysql://|postgresql://|mongodb://.*:.*@",
  output_mode="content"
)

# Step 3: Find dangerous patterns
Grep(
  pattern="eval\\(|innerHTML|dangerouslySetInnerHTML",
  type="js",
  output_mode="content",
  -C=2
)

# Step 4: Review environment variable usage
Grep(
  pattern="process\\.env",
  type="js",
  output_mode="content"
)

# Step 5: Check .env files
Glob(pattern="**/.env*")
Read(file_path="/home/fred/myapp/.env.example")

# Step 6: Audit dependencies
Bash(
  command="npm audit",
  description="Run npm security audit"
)

# Step 7: Check for outdated dependencies
Bash(
  command="npm outdated",
  description="Check for outdated packages"
)

# Step 8: Review .gitignore
Read(file_path="/home/fred/myapp/.gitignore")
Edit(
  file_path="/home/fred/myapp/.gitignore",
  old_string=".env",
  new_string=".env\n.env.local\n.env.*.local"
)
```

---

## Quick Command Reference

### Glob Patterns
```bash
*                    # All files in directory
**/*                 # All files recursively
*.js                 # All .js files
**/*.{js,ts}         # All .js and .ts files recursively
**/test/**           # All files in test directories
**/*.test.js         # All test files
**/[A-Z]*.js         # Files starting with capital letter
```

### Grep Patterns (Regex)
```bash
\bword\b             # Exact word match
function\s+\w+       # Function declarations
import.*from         # Import statements
class\s+\w+          # Class declarations
TODO:|FIXME:         # Code comments
console\.log         # console.log (escape dot)
\d{3}-\d{4}          # Phone pattern
```

### Bash Common Commands
```bash
ls -la               # List files with details
tree -L 2            # Directory tree (2 levels)
git status           # Git working tree status
npm test             # Run tests
npm run build        # Build project
find . -name "*.js"  # Find files (prefer Glob)
grep -r "pattern"    # Search content (prefer Grep)
```

---

## Summary

**Key Takeaways:**

1. **Use specialized tools**: Glob for files, Grep for content, Read for reading, Edit for modifications
2. **Always read before write/edit**: Required for existing files
3. **Parallel when possible**: Run independent operations simultaneously
4. **Absolute paths in WSL**: Use Linux-style paths (`/home/fred/...` or `/mnt/c/...`)
5. **Performance matters**: Use `type` parameter, limit scope, choose appropriate output modes
6. **Bash for commands only**: Don't use Bash for file operations when specialized tools exist

**Tool Selection Guide:**

- Need to find files by name? → **Glob**
- Need to search file contents? → **Grep**
- Need to read a file? → **Read**
- Need to create a new file? → **Write**
- Need to modify existing file? → **Edit** (preferred) or **Write**
- Need to run a command? → **Bash**

---

## Additional Resources

- Claude Code Documentation: Official documentation and examples
- Ripgrep Documentation: Advanced regex patterns and features
- Glob Pattern Guide: Comprehensive glob syntax reference
- WSL Path Guide: Understanding WSL filesystem integration

---

**Version:** 1.0
**Last Updated:** 2026-01-21
**Author:** Created for dotfiles documentation
