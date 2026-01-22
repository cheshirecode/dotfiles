# Claude Code Migration Plan (Revised)

## Overview
Extract generic, reusable development guidelines from Cursor-specific `.cursor/` configuration and create Claude Code compatible documentation at the ROOT level for all Claude instances to adopt and reuse.

## Findings from .cursor/ Directory

### Current Structure
- `.cursor/mcp.json` - MCP server configurations (Cursor-specific)
- `.cursor/rules/` - Development rule files:
  - `01-development-guidelines.mdc` - Core development guidelines
  - `04-typescript.mdc` - React + TypeScript guide (comprehensive, 700+ lines)
  - `05-auto-dev.mdc` - Automated development workflow
  - `06-github-mcp.mdc` - GitHub MCP integration
  - `07-unit-testing-guidelines.mdc` - Testing guidelines
  - `08-vercel-deployment.mdc` - Vercel deployment guidelines
  - `09-comprehensive-verification.mdc` - Verification checklist

### Tool Mapping: Cursor → Claude Code

| Cursor Tool     | Claude Code Tool | Usage |
|----------------|------------------|-------|
| `list_dir`     | `Bash` (ls) or `Glob` | List files or pattern matching |
| `file_search`  | `Glob`           | Pattern-based file finding |
| `grep_search`  | `Grep`           | Content search |
| `codebase_search` | `Grep`        | Use with appropriate patterns |
| `read_file`    | `Read`           | Direct file reading |

## Implementation Plan

### Phase 0: Structure & Format Definition
**Goal**: Establish clear specifications before implementation

**Tasks**:
1. **Decide on file organization** - Use hybrid approach:
   ```
   /CLAUDE.md (Comprehensive, ~1100 lines)
   /SETUP-CLAUDE.md (Installation guide)
   /claude-mcp.example.json (Template with comments)
   /docs/workflows.md (Reusable patterns)
   /docs/mcp-servers.md (MCP documentation)
   /docs/tool-mapping.md (Reference guide)
   ```

2. **Content classification**:
   - **Generic**: Development philosophy, git practices, testing principles
   - **Examples**: TypeScript/React specifics (clearly marked)
   - **Adaptable**: Deployment patterns, verification checklists

3. **Define workflows format**:
   - Each workflow: When to use, Steps, Claude Code commands, Examples, Tips

### Phase 1: Create Root-Level CLAUDE.md
**Goal**: Comprehensive guide for using Claude Code with best practices

**File**: `/home/fred/projects/dotfiles/CLAUDE.md`

**Content Structure** (~1100 lines):

1. **Introduction & Quick Start** (100 lines)
   - What is Claude Code
   - Quick reference for common tasks
   - Navigation guide
   - Tool overview (Glob, Grep, Read, Bash, Edit, Write)

2. **Development Philosophy** (200 lines)
   - Core approach (from 01-development-guidelines.mdc)
   - Verification and research practices
   - Deep understanding before coding
   - Autonomous problem-solving
   - Comprehensive verification
   - File-by-file changes
   - Preserve existing code

3. **Code Quality Standards** (150 lines)
   - Explicit variable names
   - Consistent coding style
   - Performance & security priorities
   - Test coverage requirements
   - Error handling
   - Modular design
   - Version compatibility
   - Edge case handling
   - Parameterization vs hardcoding
   - Dependency hygiene

4. **Language Best Practices - Examples** (400 lines)
   **CLEARLY MARKED AS TYPESCRIPT/REACT EXAMPLES**
   - Strict typing guidelines (generic TypeScript)
   - Component patterns (React examples)
   - Async operations (generic patterns)
   - State management philosophy (adaptable)
   - Performance optimization (generic concepts)
   - Testing approaches (adaptable to any framework)
   - Note: "Adapt these principles to your language/framework"

5. **Git & Version Control** (150 lines)
   - Conventional commits format
   - Atomic commits strategy (one logical change per commit)
   - Small incremental commits
   - Branch management
   - Commit message best practices
   - Git safety protocol

6. **Testing Strategy** (100 lines)
   - AAA pattern (Arrange, Act, Assert)
   - Descriptive test names
   - Test isolation
   - Mocking best practices
   - Test fixtures
   - Coverage goals (80%+)

7. **Deployment & Infrastructure** (100 lines)
   - Generic deployment workflow
   - Environment variable management
   - Pre-deployment verification
   - Post-deployment validation
   - Rollback strategy

8. **Quality Checklist** (100 lines)
   - Pre-commit checks
   - Build verification
   - Linting and formatting
   - Test execution
   - Accessibility testing
   - Error state handling
   - Responsive design
   - Documentation updates

### Phase 2: Create Claude Code MCP Configuration
**Goal**: Provide example MCP configuration for Claude Code

**File**: `/home/fred/projects/dotfiles/claude-mcp.example.json`

**Approach**:
1. Create example configuration with comments
2. Mark servers by category:
   - **Core** (recommended): sequential-thinking, filesystem
   - **Optional** (useful): github, web-search
   - **Experimental** (untested): context7, browsertools
   - **Project-specific**: figma, vercel
3. Include setup instructions as comments
4. Use clear placeholders: `YOUR_GITHUB_TOKEN_HERE`

**Content**:
```json
{
  "$schema": "https://modelcontextprotocol.io/schema/mcp.json",
  "mcpServers": {
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"],
      "_description": "Enhanced reasoning - RECOMMENDED"
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem"],
      "_description": "File system access - RECOMMENDED"
    },
    "github": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
        "ghcr.io/github/github-mcp-server"
      ],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "YOUR_GITHUB_TOKEN_HERE"
      },
      "_description": "GitHub API integration - Get token: https://github.com/settings/tokens",
      "_setup": "Optional - Requires GitHub personal access token"
    }
  }
}
```

### Phase 3: Create MCP Server Documentation
**Goal**: Document MCP servers, setup, and usage

**File**: `/home/fred/projects/dotfiles/docs/mcp-servers.md`

**Content**:
- Description of each server
- Setup instructions for servers requiring auth
- Compatibility notes (tested/untested)
- Troubleshooting guide
- Security considerations

### Phase 4: Create Workflows Documentation
**Goal**: Document reusable development patterns

**File**: `/home/fred/projects/dotfiles/docs/workflows.md`

**Content**:
1. **Atomic Commit Workflow**
   - When to use, steps, examples
2. **Test-Driven Development Pattern**
   - Red-Green-Refactor with Claude Code
3. **Code Review Preparation**
   - Self-review checklist
4. **Debugging Investigation**
   - Systematic problem-solving
5. **Safe Refactoring Pattern**
   - Step-by-step refactoring with tests

### Phase 5: Create Tool Mapping Reference
**Goal**: Help Cursor users transition

**File**: `/home/fred/projects/dotfiles/docs/tool-mapping.md`

**Content**:
- Cursor → Claude Code tool mapping table
- Usage examples for each tool
- Best practices for Claude Code tools
- Common patterns and anti-patterns

### Phase 6: Create Setup Guide
**Goal**: Help users adopt these practices

**File**: `/home/fred/projects/dotfiles/SETUP-CLAUDE.md`

**Content**:
1. **Prerequisites**
   - Claude Code installation
   - Node.js/npx for MCP servers
   - Docker (optional, for GitHub MCP)

2. **Installation Steps**
   - Copy `claude-mcp.example.json` to `~/.config/claude/mcp.json`
   - Set up API keys/tokens
   - Verify MCP servers load
   - Platform-specific notes (macOS/Linux/Windows)

3. **Usage Guide**
   - How to use CLAUDE.md
   - How to apply workflows
   - Common Claude Code commands

4. **For Cursor Users**
   - Migration checklist
   - Tool mapping reference
   - What's different, what's the same

5. **Troubleshooting**
   - Common issues
   - MCP server problems
   - Authentication failures

6. **Security Considerations**
   - API key management
   - .gitignore recommendations
   - Environment variables

### Phase 7: Update README
**Goal**: Document the Claude Code integration

**File**: `/home/fred/projects/dotfiles/README.md`

**Updates**:
- Expand overview to mention Claude Code integration
- Add "Claude Code Setup" section linking to SETUP-CLAUDE.md
- Add "Documentation Structure" section:
  - `.cursor/` - Cursor-specific configs (maintained separately)
  - Root-level files - Claude Code compatible, reusable
  - `docs/` - Supporting documentation
- Link to CLAUDE.md as main reference

### Phase 8: Validation & Testing
**Goal**: Ensure everything works

**Tasks**:
1. **Documentation review**
   - Check all links work
   - Verify code examples are correct
   - Ensure clarity and completeness

2. **MCP configuration test**
   - Test at least core MCP servers (sequential-thinking, filesystem)
   - Document any compatibility issues
   - Update docs with findings

3. **Fresh setup test**
   - Follow SETUP-CLAUDE.md from scratch
   - Document any unclear steps
   - Refine based on experience

4. **Cross-reference check**
   - Ensure all internal links work
   - Verify tool references are correct
   - Check for broken references

## File Changes Summary

### New Files to Create (Root Level)
1. `/home/fred/projects/dotfiles/CLAUDE.md` - Main documentation (~1100 lines)
2. `/home/fred/projects/dotfiles/SETUP-CLAUDE.md` - Setup guide
3. `/home/fred/projects/dotfiles/claude-mcp.example.json` - MCP config template
4. `/home/fred/projects/dotfiles/docs/workflows.md` - Development workflows
5. `/home/fred/projects/dotfiles/docs/mcp-servers.md` - MCP documentation
6. `/home/fred/projects/dotfiles/docs/tool-mapping.md` - Cursor→Claude reference

### Files to Update
1. `/home/fred/projects/dotfiles/README.md` - Add Claude Code section

### Directories to Create
1. `/home/fred/projects/dotfiles/docs/` - Supporting documentation

## Key Principles for Migration

### What to Keep Generic
- Development philosophy and approach
- Code quality standards
- Git commit conventions
- Testing strategies (AAA pattern, isolation, etc.)
- Deployment verification steps
- Error handling principles

### What to Mark as Examples
- TypeScript/React specific patterns (clearly labeled)
- Framework-specific state management
- Project-specific tech stack choices
- Note: "These are examples - adapt to your stack"

### What to Adapt
- Cursor tool references → Claude Code tools
- MCP configuration format
- Auto-dev workflow → Extract principles only
- Tool-specific commands → Generic patterns

### What to Add
- Claude Code tool usage guide (Glob, Grep, Read, Bash, etc.)
- Claude Code MCP setup instructions
- Tool mapping for Cursor users
- Platform-specific setup notes
- Security best practices

## Success Criteria

1. **Documentation Quality**
   - [ ] CLAUDE.md is comprehensive with working table of contents
   - [ ] All code examples are correct and tested
   - [ ] Generic content clearly separated from examples
   - [ ] No broken references or placeholders
   - [ ] Average reader can complete setup in < 30 minutes

2. **MCP Configuration**
   - [ ] claude-mcp.example.json uses correct Claude Code format
   - [ ] All MCP servers documented with setup instructions
   - [ ] Authentication requirements clearly explained
   - [ ] At least 2 core MCP servers tested and verified

3. **Usability**
   - [ ] Users can adopt practices without prior Cursor knowledge
   - [ ] Examples are practical and copy-paste ready
   - [ ] Setup guide is clear and complete
   - [ ] Platform differences documented

4. **Completeness**
   - [ ] All valuable guidelines from .cursor/ captured
   - [ ] Tool mappings documented
   - [ ] Workflows extractable and reusable
   - [ ] Both Cursor and Claude Code users can benefit

5. **Organization**
   - [ ] Logical file structure (root vs docs/)
   - [ ] Clear navigation between documents
   - [ ] README provides good overview
   - [ ] Files are in root for easy adoption

## Content Extraction Matrix

| Source File | Sections | Adaptations | Target |
|-------------|----------|-------------|--------|
| 01-development-guidelines.mdc | Core Approach (lines 12-15) | Update tool names | CLAUDE.md §2 |
| 01-development-guidelines.mdc | Guidelines 1-23 (lines 16-106) | Generic | CLAUDE.md §3 |
| 04-typescript.mdc | TypeScript Best Practices (lines 37-127) | Mark as examples | CLAUDE.md §4 |
| 04-typescript.mdc | React Best Practices (lines 129-177) | Mark as examples | CLAUDE.md §4 |
| 04-typescript.mdc | Atomic Commits (lines 402-424) | Generic | CLAUDE.md §5 |
| 07-unit-testing-guidelines.mdc | All sections | Generic | CLAUDE.md §6 |
| 08-vercel-deployment.mdc | Generic workflow | Remove Vercel-specific | CLAUDE.md §7 |
| 09-comprehensive-verification.mdc | All checklists | Generic | CLAUDE.md §8 |
| 05-auto-dev.mdc | Workflow principles | Extract concepts only | docs/workflows.md |
| 06-github-mcp.mdc | GitHub integration | Adapt for Claude Code | docs/mcp-servers.md |
| .cursor/mcp.json | Server configs | Test & document | claude-mcp.example.json |

## Next Steps

1. ✅ Review this plan with code review agent
2. ✅ Incorporate feedback
3. Create docs/ directory structure
4. Implement Phase 1 (CLAUDE.md)
5. Implement Phase 2 (claude-mcp.example.json)
6. Implement Phase 3 (docs/mcp-servers.md)
7. Implement Phase 4 (docs/workflows.md)
8. Implement Phase 5 (docs/tool-mapping.md)
9. Implement Phase 6 (SETUP-CLAUDE.md)
10. Implement Phase 7 (README update)
11. Implement Phase 8 (Validation)
12. Commit and push all changes
