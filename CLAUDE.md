# Claude Code Development Guidelines

> Comprehensive guide for using Claude Code with best practices for software development

**Version**: 1.0.0
**Last Updated**: 2026-01-21

---

## Commit hygiene (forward-discipline; lesson from a past bundled commit)

A single commit should advance a single concern. When work touches both
**guidance/posture text** (this file, README.md) AND **behavioral guards**
(bin/*.sh, manifest, hooks), split into separate commits even if they
landed in the same edit session. Reviewers reading destructive-command
guardrails should not have to skip over a karpathy preamble (and vice
versa); the diff lenses differ.

Past anti-pattern (kept here so we don't repeat it): commit `98cd75f`
bundled "karpathy posture preamble" with "git reset --hard preconditions"
— two separable concerns. The council that audited it (Stage 6 item #6)
rejected retroactive `git rebase -i` + force-push as net-negative; the
correction lives forward in this rule.

## Checkout and branch discipline (lesson from detached Codex worktrees)

When the user targets `oss/dotfiles` or `/Users/fredtran/Documents/oss/dotfiles`,
use that primary checkout on `main` as the delivery surface and commit directly
to `main` unless the user explicitly asks for a branch or PR.

Temporary agent worktrees under `.codex/worktrees/.../dotfiles` may be detached
or branch-prefixed by default. Treat them as scratch/integration surfaces only:
if work starts there, port or merge the exact changes back into the primary
`oss/dotfiles` checkout, validate from that checkout, and push `main` from
there. Do not let "detached HEAD" in a temporary worktree silently turn a
direct-main request into a side branch.

## Reading posture (apply before treating any section as a recipe)

This is a guidance document, not a runnable checklist. When an agent reads
it as input, apply Karpathy's four guidelines first:

1. **Think before coding** — surface assumptions explicitly; ask if multiple
   interpretations exist.
2. **Simplicity first** — minimum diff that solves the asked problem; no
   speculative abstraction; no error handling for impossible cases.
3. **Surgical changes** — every changed line must trace to the user's
   request. No drive-by refactoring, no whitespace edits, no "while I'm
   here" cleanup.
4. **Goal-driven execution** — every step carries a verifiable check; loop
   until checks pass; never declare done without citing a verify command's
   exit code or output.

Commands shown below are illustrative. Destructive ones (`git reset --hard`,
`rm -rf`, force-push) are documented as DANGEROUS with explicit guardrails
in their respective sections; agents must honor those guardrails as
preconditions, not skip past them.

---

## Table of Contents

1. [Introduction & Quick Start](#introduction--quick-start)
   - [What is Claude Code](#what-is-claude-code)
   - [Claude Code Tools Overview](#claude-code-tools-overview)
   - [Quick Reference](#quick-reference)
   - [Navigation Guide](#navigation-guide)
   - [Environment Considerations](#environment-considerations)

2. [Development Philosophy](#development-philosophy)
   - [Core Approach](#core-approach)
   - [Verification and Research Practices](#verification-and-research-practices)
   - [Deep Understanding Before Coding](#deep-understanding-before-coding)
   - [Autonomous Problem-Solving](#autonomous-problem-solving)
   - [Comprehensive Verification](#comprehensive-verification)
   - [File-by-File Changes](#file-by-file-changes)
   - [Preserve Existing Code](#preserve-existing-code)

3. [Code Quality Standards](#code-quality-standards)
   - [Explicit Variable Names](#explicit-variable-names)
   - [Consistent Coding Style](#consistent-coding-style)
   - [Performance and Security Priorities](#performance-and-security-priorities)
   - [Test Coverage Requirements](#test-coverage-requirements)
   - [Error Handling](#error-handling)
   - [Modular Design](#modular-design)
   - [Version Compatibility](#version-compatibility)
   - [Edge Case Handling](#edge-case-handling)
   - [Parameterization vs Hardcoding](#parameterization-vs-hardcoding)
   - [Dependency Hygiene](#dependency-hygiene)

4. [Language Best Practices - EXAMPLES](#language-best-practices---examples)
   - [IMPORTANT: TypeScript/React Examples](#important-typescriptreact-examples)
   - [Strict Typing Guidelines](#strict-typing-guidelines)
   - [Component Patterns](#component-patterns)
   - [Async Operations](#async-operations)
   - [State Management Philosophy](#state-management-philosophy)
   - [Performance Optimization](#performance-optimization)
   - [Testing Approaches](#testing-approaches)

5. [Git & Version Control](#git--version-control)
   - [Conventional Commits Format](#conventional-commits-format)
   - [Atomic Commits Strategy](#atomic-commits-strategy)
   - [Small Incremental Commits](#small-incremental-commits)
   - [Branch Management](#branch-management)
   - [Commit Message Best Practices](#commit-message-best-practices)
   - [Git Safety Protocol](#git-safety-protocol)

6. [Testing Strategy](#testing-strategy)
   - [AAA Pattern](#aaa-pattern)
   - [Descriptive Test Names](#descriptive-test-names)
   - [Test Isolation](#test-isolation)
   - [Mocking Best Practices](#mocking-best-practices)
   - [Test Fixtures](#test-fixtures)
   - [Coverage Goals](#coverage-goals)

7. [Deployment & Infrastructure](#deployment--infrastructure)
   - [Generic Deployment Workflow](#generic-deployment-workflow)
   - [Environment Variable Management](#environment-variable-management)
   - [Pre-Deployment Verification](#pre-deployment-verification)
   - [Post-Deployment Validation](#post-deployment-validation)
   - [Rollback Strategy](#rollback-strategy)

8. [Quality Checklist](#quality-checklist)
   - [Pre-Commit Checks](#pre-commit-checks)
   - [Build Verification](#build-verification)
   - [Linting and Formatting](#linting-and-formatting)
   - [Test Execution](#test-execution)
   - [Accessibility Testing](#accessibility-testing)
   - [Error State Handling](#error-state-handling)
   - [Responsive Design](#responsive-design)
   - [Documentation Updates](#documentation-updates)

---

## Introduction & Quick Start

### What is Claude Code

Claude Code is Anthropic's official CLI for Claude, enabling you to leverage Claude's capabilities directly in your development workflow. It provides a powerful set of tools for code analysis, file manipulation, testing, and deployment automation.

This document provides comprehensive guidelines for using Claude Code effectively across any technology stack. While some examples use TypeScript/React, the core principles apply universally.

### Claude Code Tools Overview

Claude Code provides specialized tools for different development tasks:

| Tool | Purpose | Use Cases |
|------|---------|-----------|
| **Glob** | Pattern-based file finding | Find files by extension, name patterns, directory structure |
| **Grep** | Content search across files | Search for functions, variables, patterns, imports |
| **Read** | Read file contents | View source code, configuration files, documentation |
| **Edit** | Modify file contents | Update existing code, fix bugs, refactor |
| **Write** | Create new files | Generate new components, tests, configuration |
| **Bash** | Execute shell commands | Run tests, build projects, git operations, package management |

**Key Principles**:
- Use **Glob** when you need to find files matching patterns (e.g., `**/*.test.ts`)
- Use **Grep** when you need to search file contents (e.g., finding function definitions)
- Use **Read** when you know the exact file path
- Use **Edit** for surgical code changes
- Use **Write** only when creating new files
- Use **Bash** for running commands, but prefer specialized tools for file operations

### Quick Reference

**Common Tasks**:

```bash
# Find all TypeScript files
Glob: "**/*.ts"

# Search for a function definition
Grep: "function processData" --output_mode content

# Read a specific file
Read: /path/to/file.ts

# Run tests
Bash: npm test

# Check git status
Bash: git status

# Create a new component (only when necessary)
Write: /path/to/Component.tsx
```

### Navigation Guide

- **Getting Started**: Read [Development Philosophy](#development-philosophy) first
- **Code Standards**: See [Code Quality Standards](#code-quality-standards)
- **Version Control**: Check [Git & Version Control](#git--version-control)
- **Examples**: Language-specific patterns in [Language Best Practices](#language-best-practices---examples)
- **Testing**: Full testing guide in [Testing Strategy](#testing-strategy)
- **Deployment**: Infrastructure patterns in [Deployment & Infrastructure](#deployment--infrastructure)
- **Quality Checks**: Pre-commit checklist in [Quality Checklist](#quality-checklist)

### Environment Considerations

#### WSL (Windows Subsystem for Linux)

If you're running Claude Code in WSL, be aware of these considerations:

**Path Handling**:
- WSL file paths use Linux format: `/home/user/project`
- Windows paths are accessible via: `/mnt/c/Users/...`
- Git operations work natively in WSL
- Use Linux-style paths for all Claude Code operations

**Performance**:
- Keep project files in the WSL filesystem (`/home/...`) for best performance
- Avoid working directly in `/mnt/c/...` when possible (slower I/O)
- Git operations are significantly faster in native WSL filesystem

**Docker Integration**:
- Docker Desktop for Windows integrates with WSL2
- MCP servers using Docker (like GitHub MCP) work seamlessly
- Ensure Docker Desktop has WSL2 integration enabled

**Environment Variables**:
- Set environment variables in `~/.bashrc` or `~/.zshrc`
- WSL environment is separate from Windows environment
- Use `wslpath` to convert between Windows and WSL paths if needed

**Common WSL Commands**:
```bash
# Convert Windows path to WSL path
wslpath 'C:\Users\YourName\project'
# Returns: /mnt/c/Users/YourName/project

# Convert WSL path to Windows path
wslpath -w /home/user/project
# Returns: \\wsl$\Ubuntu\home\user\project

# Access Windows files from WSL
cd /mnt/c/Users/YourName/Documents

# Check WSL version
wsl --version
```

**Best Practices for WSL**:
- Clone repositories directly in WSL home directory
- Configure Git with WSL-specific settings
- Use WSL-native tools (not Windows executables)
- Keep development dependencies in WSL (npm, node, python, etc.)

---

## Development Philosophy

### Core Approach

Act as a skilled, proactive, and meticulous senior colleague. Take ownership of tasks, operating with diligence and foresight. Your objective is to deliver polished, well-designed results with minimal interaction required.

**Key Principles**:
- **Use tools extensively** for context gathering, research, and verification
- **Verify before presenting** - don't make assumptions without evidence
- **Deep understanding** - investigate thoroughly before coding
- **Autonomous problem-solving** - resolve ambiguities independently
- **Comprehensive verification** - rigorously test before presenting
- **Incremental changes** - make changes file-by-file for review
- **Respect existing code** - preserve unrelated functionality

### Verification and Research Practices

**Always verify information before presenting it**. Use Claude Code tools to gather context:

```bash
# Step 1: Understand the codebase structure
Glob: "**/*.{ts,tsx,js,jsx}"

# Step 2: Search for related implementations
Grep: "similar-function-name" --output_mode content

# Step 3: Read relevant files
Read: /path/to/related-file.ts

# Step 4: Verify your understanding
Grep: "import.*MyComponent" --output_mode files_with_matches
```

**Research Workflow**:
1. Use **Glob** to find relevant files
2. Use **Grep** to search for patterns and implementations
3. Use **Read** to understand existing code
4. Verify assumptions with additional searches
5. Present findings with evidence

### Deep Understanding Before Coding

**Do not rush to code**. Spend time understanding:
- Existing architecture and patterns
- Related implementations
- Dependencies and side effects
- Test coverage and requirements
- Documentation and comments

**Investigation Process**:
```bash
# Find all related files
Glob: "**/*authentication*"

# Search for similar patterns
Grep: "authProvider" --output_mode content

# Read implementation details
Read: /src/auth/AuthProvider.tsx

# Find usage examples
Grep: "useAuth" --output_mode files_with_matches

# Check tests
Grep: "describe.*Auth" --output_mode content
```

### Autonomous Problem-Solving

When requests are ambiguous:
1. **Don't ask immediately** - investigate first
2. Use tools to understand context
3. Find similar implementations
4. Identify patterns and conventions
5. Make informed decisions
6. Document assumptions clearly

**Example**: "Add error handling" is ambiguous. Instead of asking, investigate:
- How errors are handled elsewhere
- What error types exist
- What error UI components are available
- What logging mechanisms are used

### Comprehensive Verification

Rigorously verify work before presenting:

**Verification Checklist**:
- [ ] Code compiles/transpiles successfully
- [ ] All tests pass
- [ ] Linting rules satisfied
- [ ] Type checking passes (if applicable)
- [ ] No regressions in existing functionality
- [ ] Edge cases considered
- [ ] Error handling implemented
- [ ] Documentation updated

**Verification Commands**:
```bash
# Run full verification suite
Bash: npm run build && npm test && npm run lint

# Type checking (TypeScript)
Bash: tsc --noEmit

# Test specific file
Bash: npm test -- path/to/file.test.ts

# Check formatting
Bash: prettier --check "src/**/*.{ts,tsx}"
```

### File-by-File Changes

**Make changes file-by-file** and allow for review between modifications.

**Anti-pattern**: Changing 10 files at once
**Best practice**: Change 1-3 closely related files, then pause for review

**Grouping Rules**:
- Single file changes: Ideal
- Component + styles: Acceptable (inseparable)
- Component + test: Acceptable (related)
- Component + styles + test: Maximum acceptable group
- Multiple unrelated files: Break into separate changes

### Preserve Existing Code

**Respect existing structures and functionality**:
- Don't remove unrelated code
- Don't refactor unless explicitly asked
- Don't change coding style unnecessarily
- Don't modify working functionality
- Don't update dependencies without discussion

**Example**:
```typescript
// ❌ BAD: Removed unrelated functionality
export function processData(data: string): string {
  return data.toUpperCase(); // Removed validation and formatting
}

// ✅ GOOD: Preserved existing functionality, added new feature
export function processData(data: string): string {
  // Existing validation
  if (!data) throw new Error('Data is required');

  // Existing formatting
  const formatted = data.trim();

  // NEW: Added uppercase transformation
  return formatted.toUpperCase();
}
```

---

## Code Quality Standards

### Explicit Variable Names

Use descriptive, self-documenting variable names:

```typescript
// ❌ BAD: Ambiguous, short names
const d = new Date();
const u = getUserData();
const res = await fetch(url);

// ✅ GOOD: Clear, descriptive names
const currentDate = new Date();
const userData = getUserData();
const apiResponse = await fetch(url);
```

**Naming Conventions**:
- **Variables**: `camelCase`, descriptive nouns
- **Functions**: `camelCase`, action verbs
- **Constants**: `UPPER_SNAKE_CASE` or `camelCase` depending on language
- **Classes**: `PascalCase`, singular nouns
- **Booleans**: Prefix with `is`, `has`, `should`, `can`

### Consistent Coding Style

**Follow the existing coding style in the project**:
- Indentation (spaces vs tabs)
- Quotes (single vs double)
- Semicolons (present vs omitted)
- Line length limits
- Import ordering
- Comment style

**Use project tools**:
```bash
# Check existing configuration
Read: .editorconfig
Read: .prettierrc
Read: .eslintrc.json

# Format code
Bash: npm run format

# Lint code
Bash: npm run lint -- --fix
```

### Performance and Security Priorities

**Consider performance implications**:
- Avoid unnecessary re-renders (React)
- Use efficient data structures
- Minimize network requests
- Implement caching where appropriate
- Optimize expensive computations
- Use lazy loading for large resources

**Consider security aspects**:
- Validate all user inputs
- Sanitize data before rendering
- Use parameterized queries (SQL)
- Avoid exposing sensitive data
- Implement proper authentication/authorization
- Use HTTPS for API calls
- Handle secrets securely (environment variables)

**Security Checklist**:
- [ ] No hardcoded secrets or API keys
- [ ] Input validation implemented
- [ ] Output encoding/escaping used
- [ ] Authentication checked
- [ ] Authorization verified
- [ ] Secure communication (HTTPS)
- [ ] Dependencies up to date

### Test Coverage Requirements

**Aim for 80%+ test coverage** for:
- Business logic functions
- Utility functions
- API clients
- Critical user flows
- Edge cases and error handling

**What to test**:
- ✅ Business logic and calculations
- ✅ Data transformations
- ✅ API integrations
- ✅ User interactions
- ✅ Error handling
- ✅ Edge cases

**What not to test**:
- ❌ Third-party library internals
- ❌ Simple getters/setters
- ❌ Trivial functions
- ❌ Configuration files

### Error Handling

**Implement robust error handling**:

```typescript
// ✅ GOOD: Comprehensive error handling
async function fetchUserData(userId: string): Promise<User> {
  try {
    const response = await fetch(`/api/users/${userId}`);

    if (!response.ok) {
      throw new ApiError(response.status, response.statusText);
    }

    return await response.json();
  } catch (error) {
    if (error instanceof ApiError) {
      // Handle API errors
      logger.error('API Error:', error.message);
      throw error;
    } else if (error instanceof TypeError) {
      // Handle network errors
      logger.error('Network Error:', error.message);
      throw new NetworkError('Failed to fetch user data');
    } else {
      // Handle unexpected errors
      logger.error('Unexpected Error:', error);
      throw new UnexpectedError('An unexpected error occurred');
    }
  }
}
```

**Error Handling Best Practices**:
- Use specific error types
- Provide actionable error messages
- Log errors appropriately
- Don't swallow errors silently
- Handle errors at appropriate levels
- Provide fallback UI for user-facing errors

### Modular Design

**Follow modular design principles**:
- Single Responsibility Principle (SRP)
- Separation of Concerns
- Don't Repeat Yourself (DRY)
- Keep functions small and focused
- Extract reusable logic
- Clear interfaces between modules

**Example**:
```typescript
// ❌ BAD: God function doing everything
function processUserRegistration(email: string, password: string) {
  // Validate email
  // Validate password
  // Hash password
  // Save to database
  // Send welcome email
  // Log analytics
  // Return user
}

// ✅ GOOD: Modular, single-purpose functions
function validateEmail(email: string): void { }
function validatePassword(password: string): void { }
function hashPassword(password: string): string { }
function saveUser(user: User): Promise<User> { }
function sendWelcomeEmail(user: User): Promise<void> { }
function logUserRegistration(userId: string): void { }

async function processUserRegistration(
  email: string,
  password: string
): Promise<User> {
  validateEmail(email);
  validatePassword(password);

  const hashedPassword = hashPassword(password);
  const user = await saveUser({ email, password: hashedPassword });

  await sendWelcomeEmail(user);
  logUserRegistration(user.id);

  return user;
}
```

### Version Compatibility

**Ensure changes are compatible**:
- Check required language/runtime versions
- Verify dependency versions
- Test on target platforms
- Document version requirements
- Use version managers (nvm, pyenv, rbenv)

**Check compatibility**:
```bash
# Check Node.js version
Read: .nvmrc
Read: package.json  # engines field

# Check Python version
Read: .python-version
Read: pyproject.toml

# Check runtime versions
Bash: node --version
Bash: python --version
```

### Edge Case Handling

**Consider and handle edge cases**:
- Null/undefined values
- Empty arrays/objects
- Zero/negative numbers
- Very large numbers
- Special characters in strings
- Concurrent operations
- Network failures
- Timeout scenarios

**Example**:
```typescript
function calculateAverage(numbers: number[]): number {
  // Handle empty array
  if (numbers.length === 0) {
    throw new Error('Cannot calculate average of empty array');
  }

  // Handle invalid numbers
  const validNumbers = numbers.filter(n => !isNaN(n) && isFinite(n));
  if (validNumbers.length === 0) {
    throw new Error('No valid numbers to calculate average');
  }

  const sum = validNumbers.reduce((acc, n) => acc + n, 0);
  return sum / validNumbers.length;
}
```

### Parameterization vs Hardcoding

**Prefer parameterization with sensible defaults** over hardcoding values.

**When to parameterize**:
- ✅ Values that might change based on requirements
- ✅ Values that improve testability
- ✅ Values that make code reusable
- ✅ Configuration from external sources

**When hardcoding is acceptable**:
- ✅ Truly immutable constants
- ✅ UI-specific strings that never change
- ✅ Performance-critical paths where abstraction hurts

**Example**:
```typescript
// ❌ BAD: Hardcoded in function
function fetchProducts() {
  const types = ['FIXED', 'VARIABLE']; // hardcoded
  return api.get('/products', { types });
}

// ✅ GOOD: Parameterized with default from constants
const DEFAULT_PRODUCT_TYPES = ['FIXED', 'VARIABLE'] as const;

function fetchProducts(
  types: readonly string[] = DEFAULT_PRODUCT_TYPES
): Promise<Product[]> {
  return api.get('/products', { types });
}
```

### Dependency Hygiene

**When removing a package, search for ALL references**:

```bash
# Search across entire codebase
Grep: "package-name" --output_mode files_with_matches

# Check specific locations
Grep: "package-name" --path src/
Grep: "package-name" --path docs/
Grep: "package-name" --glob "*.md"

# Check imports
Grep: "from ['\"]package-name" --output_mode content

# Check package.json
Read: package.json
```

**Before removing a dependency**:
1. Search all source code
2. Search all documentation
3. Search configuration files
4. Search test files
5. Remove from package.json
6. Run tests to verify
7. Commit the complete removal

---

## Language Best Practices - EXAMPLES

### IMPORTANT: TypeScript/React Examples

**⚠️ The following sections contain TypeScript/React-specific examples.**

**These are EXAMPLES to illustrate principles** - adapt them to your language and framework:
- **Python**: Apply strict typing with mypy, type hints
- **Java**: Apply strong typing, interfaces
- **Go**: Apply explicit types, interfaces
- **Rust**: Apply ownership, traits
- **Ruby**: Apply RBS/Sorbet for typing
- **PHP**: Apply strict types, interfaces

**The PRINCIPLES are universal** - the syntax is just an example.

### Strict Typing Guidelines

**Use the strictest type checking available in your language**:

**TypeScript Example**:
```typescript
// ✅ GOOD: Strict types, no implicit any
interface User {
  id: string;
  email: string;
  name: string;
  role: 'admin' | 'user' | 'guest';
}

function getUser(id: string): Promise<User> {
  return api.get<User>(`/users/${id}`);
}

// ❌ BAD: Implicit any, loose types
function getUser(id): Promise<any> {
  return api.get(`/users/${id}`);
}
```

**Python Example** (equivalent principle):
```python
# ✅ GOOD: Type hints with mypy strict mode
from typing import Literal

UserRole = Literal['admin', 'user', 'guest']

class User:
    id: str
    email: str
    name: str
    role: UserRole

def get_user(id: str) -> User:
    return api.get(f'/users/{id}')

# ❌ BAD: No type hints
def get_user(id):
    return api.get(f'/users/{id}')
```

**Typing Principles (Universal)**:
- Use explicit types everywhere
- Avoid dynamic/any types
- Use union types for variants
- Use enums/literals for fixed values
- Enforce type checking in CI/CD

### Component Patterns

**TypeScript/React Example**:
```typescript
// ✅ GOOD: Explicit props interface, no React.FC
interface ButtonProps {
  children: React.ReactNode;
  onClick: (e: React.MouseEvent<HTMLButtonElement>) => void;
  disabled?: boolean;
  variant?: 'primary' | 'secondary' | 'ghost';
}

export function Button({
  children,
  onClick,
  disabled = false,
  variant = 'primary'
}: ButtonProps): JSX.Element {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`btn btn-${variant}`}
    >
      {children}
    </button>
  );
}
```

**Principles (Adapt to your stack)**:
- Explicit prop/parameter types
- Default values clearly defined
- Single responsibility per component
- Props interface at top of file
- Return type explicitly stated

### Async Operations

**TypeScript Example**:
```typescript
// ✅ GOOD: Explicit Promise type, timeout, error handling
export async function fetchData(id: string): Promise<Data> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25000);

  try {
    const res = await fetch(`/api/data/${id}`, {
      signal: controller.signal,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    });

    if (!res.ok) {
      throw new ApiError(res.status, res.statusText);
    }

    return await res.json();
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') {
      throw new TimeoutError('Request timed out after 25s');
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}
```

**Python Example** (equivalent principle):
```python
import asyncio
from typing import TypedDict

class Data(TypedDict):
    id: str
    value: str

async def fetch_data(id: str) -> Data:
    try:
        async with asyncio.timeout(25):
            response = await client.get(
                f'/api/data/{id}',
                headers={
                    'Accept': 'application/json',
                    'Content-Type': 'application/json',
                }
            )

            if response.status_code != 200:
                raise ApiError(response.status_code, response.reason)

            return response.json()
    except asyncio.TimeoutError:
        raise TimeoutError('Request timed out after 25s')
```

**Async Principles (Universal)**:
- Explicit return types for async functions
- Timeout handling
- Proper error handling
- Resource cleanup (try/finally)
- Cancellation support where applicable

### State Management Philosophy

**Decision Tree (Universal)**:
1. **Server/API state?** → Use data fetching library (SWR, React Query, Apollo)
2. **Local UI state?** → Use component state (useState, local variables)
3. **Global UI state?** → Use minimal state library (Jotai, Zustand, Redux)
4. **Prop drilling (>3 levels)?** → Use Context or state library

**React Example**:
```typescript
// Server state - SWR
const { data: products, error } = useSWR('/products', fetcher);

// Local state
const [isOpen, setIsOpen] = useState(false);

// Global state - Jotai (minimal use)
const [theme, setTheme] = useAtom(themeAtom);
```

**Principles (Adapt to your stack)**:
- Server state separate from UI state
- Start with local state, lift only when needed
- Minimize global state
- Use appropriate tools for each state type

### Performance Optimization

**React Example**:
```typescript
// ✅ GOOD: Memoize expensive computations
const filteredProducts = useMemo(
  () => products.filter(p => p.price > minPrice),
  [products, minPrice]
);

// ✅ GOOD: Memoize callbacks for child components
const handleClick = useCallback((id: string) => {
  setSelected(id);
}, []);
```

**When to optimize (Universal)**:
- Large list rendering (>100 items)
- Expensive computations
- Frequent re-renders
- Performance profiling shows bottleneck

**When NOT to optimize**:
- Premature optimization
- Simple computations
- One-time operations
- Without performance data

### Testing Approaches

**TypeScript/Vitest Example**:
```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

describe('Button', () => {
  it('calls onClick handler when clicked', async () => {
    // Arrange
    const handleClick = vi.fn();
    const user = userEvent.setup();
    render(<Button onClick={handleClick}>Click me</Button>);

    // Act
    await user.click(screen.getByRole('button'));

    // Assert
    expect(handleClick).toHaveBeenCalledTimes(1);
  });
});
```

**Python/pytest Example** (equivalent principle):
```python
def test_button_calls_handler_when_clicked():
    # Arrange
    handler = Mock()
    button = Button(on_click=handler)

    # Act
    button.click()

    # Assert
    assert handler.call_count == 1
```

**Testing Principles (Universal)**:
- Follow AAA pattern (Arrange, Act, Assert)
- Descriptive test names
- One assertion per test (generally)
- Test behavior, not implementation
- Mock external dependencies

---

## Git & Version Control

### Conventional Commits Format

Use standardized commit message format:

```
type(scope): description

[optional body]

[optional footer]
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code refactoring (no functional change)
- `test`: Adding or updating tests
- `docs`: Documentation changes
- `style`: Code style changes (formatting, whitespace)
- `perf`: Performance improvements
- `chore`: Maintenance tasks (dependencies, build config)
- `ci`: CI/CD changes
- `build`: Build system changes
- `a11y`: Accessibility improvements

**Examples**:
```bash
feat: add user authentication
fix: resolve race condition in form submission
refactor: extract validation logic to utils
test: add coverage for product filters
docs: update API documentation
style: format code with prettier
perf: optimize product list rendering
chore: update dependencies
a11y: improve keyboard navigation
```

### Atomic Commits Strategy

**One logical change per commit**:
- Single file changes are ideal
- Group only when changes are inseparable
- Each commit should be functional on its own
- Easy to review, revert, and cherry-pick

**Grouping Rules**:
```bash
# ✅ GOOD: Single file
git add src/utils/validation.ts
git commit -m "feat: add email validation function"

# ✅ GOOD: Inseparable changes (component + styles)
git add src/components/Button.tsx src/components/Button.module.css
git commit -m "feat: add primary button variant"

# ✅ GOOD: Component + test
git add src/utils/format.ts src/utils/format.test.ts
git commit -m "feat: add date formatting utility"

# ❌ BAD: Multiple unrelated changes
git add src/components/Button.tsx src/utils/api.ts src/pages/Home.tsx
git commit -m "feat: various updates"
```

### Small Incremental Commits

**Keep commits small and focused**:

Benefits:
- Easier code review
- Simpler to revert if needed
- Clear project history
- Better for git bisect
- Easier to cherry-pick

**Workflow**:
```bash
# Make small change
Edit: src/utils/validation.ts

# Commit immediately
Bash: git add src/utils/validation.ts
Bash: git commit -m "feat: add email validation"

# Make next change
Edit: src/utils/validation.ts

# Commit again
Bash: git add src/utils/validation.ts
Bash: git commit -m "test: add email validation tests"
```

### Branch Management

**Branch naming conventions**:
```
<type>/<ticket-id>-<description>

feature/123-add-user-auth
fix/456-resolve-memory-leak
refactor/789-extract-api-client
```

**Branch workflow**:
```bash
# Create feature branch
Bash: git checkout -b feature/123-add-user-auth

# Make commits
Bash: git commit -m "feat: add login component"
Bash: git commit -m "test: add login tests"

# Push to remote
Bash: git push -u origin feature/123-add-user-auth

# Create pull request
# (Use GitHub CLI or web interface)
```

### Commit Message Best Practices

**Write clear, descriptive messages**:

**Good commit messages**:
```
feat: add password reset functionality

Implements password reset flow with email verification.
Includes rate limiting to prevent abuse.

Closes #123
```

**Bad commit messages**:
```
fix stuff
wip
updates
changes
asdf
```

**Rules**:
- Use imperative mood ("add" not "added")
- Capitalize first letter
- No period at end of subject line
- Subject line ≤ 50 characters
- Body line length ≤ 72 characters
- Explain "what" and "why", not "how"

### Git Safety Protocol

**Safe git practices**:

**Never**:
- ❌ Force push to main/master
- ❌ Commit secrets or API keys
- ❌ Commit large binary files
- ❌ Rewrite public history
- ❌ Commit directly to protected branches

**Always**:
- ✅ Review changes before committing
- ✅ Use `.gitignore` for sensitive files
- ✅ Pull before pushing
- ✅ Create branches for features
- ✅ Write clear commit messages

**Useful commands**:
```bash
# Review changes before committing
Bash: git diff
Bash: git status

# Amend last commit — ONLY IF UNPUSHED.
# Guardrail: if `git config --get branch.$(git branch --show-current).remote`
# returns a remote AND `git rev-list @{push}..HEAD` is empty, the commit
# is already pushed — DO NOT amend.
Bash: git commit --amend

# Undo last commit (keep changes) — safe, non-destructive
Bash: git reset --soft HEAD~1

# Undo last commit (DISCARD changes) — DANGEROUS, REQUIRES EXPLICIT INTENT.
# Guardrails (all must hold):
#   - The branch is unpushed (`git push --dry-run` shows "Everything up-to-date"
#     is FALSE — i.e. local commits would push). If pushed, use `git revert` instead.
#   - The user explicitly typed `--hard` in their request. Do not infer
#     `--hard` from "undo my commit"; the soft form above is the safe default.
#   - Working tree is clean OR user explicitly accepts losing uncommitted work.
# An agent reading this doc as a checklist MUST refuse to run this command
# absent all three conditions.
Bash: git reset --hard HEAD~1

# Stash changes temporarily
Bash: git stash
Bash: git stash pop
```

---

## Testing Strategy

### AAA Pattern

**Follow Arrange-Act-Assert pattern**:

```typescript
describe('calculateTotal', () => {
  it('calculates total price with tax', () => {
    // Arrange - Set up test data
    const items = [
      { price: 10, quantity: 2 },
      { price: 5, quantity: 1 }
    ];
    const taxRate = 0.1;

    // Act - Execute the function
    const total = calculateTotal(items, taxRate);

    // Assert - Verify the result
    expect(total).toBe(27.5); // (10*2 + 5*1) * 1.1
  });
});
```

**Benefits**:
- Clear test structure
- Easy to understand
- Separates setup, execution, verification
- Maintainable and readable

### Descriptive Test Names

**Use descriptive test names that explain the scenario**:

```typescript
// ✅ GOOD: Clear, descriptive names
describe('UserAuthentication', () => {
  it('returns user data when credentials are valid', () => { });
  it('throws AuthError when password is incorrect', () => { });
  it('throws AuthError when user does not exist', () => { });
  it('locks account after 5 failed login attempts', () => { });
});

// ❌ BAD: Vague, unclear names
describe('UserAuthentication', () => {
  it('works', () => { });
  it('test login', () => { });
  it('error case', () => { });
});
```

**Template**: "it [does something] when [condition]"

### Test Isolation

**Keep tests focused and isolated**:

**Principles**:
- Each test should be independent
- Tests should not rely on execution order
- Clean up after each test
- Don't share mutable state between tests
- Use fresh test data for each test

```typescript
describe('TodoList', () => {
  // ✅ GOOD: Each test is isolated
  it('adds todo item', () => {
    const list = new TodoList(); // Fresh instance
    list.add('Buy milk');
    expect(list.items).toHaveLength(1);
  });

  it('removes todo item', () => {
    const list = new TodoList(); // Fresh instance
    list.add('Buy milk');
    list.remove(0);
    expect(list.items).toHaveLength(0);
  });

  // ❌ BAD: Tests depend on each other
  const sharedList = new TodoList();

  it('adds todo item', () => {
    sharedList.add('Buy milk');
    expect(sharedList.items).toHaveLength(1);
  });

  it('removes todo item', () => {
    sharedList.remove(0); // Depends on previous test
    expect(sharedList.items).toHaveLength(0);
  });
});
```

### Mocking Best Practices

**Mock external dependencies appropriately**:

**When to mock**:
- ✅ External APIs
- ✅ Database calls
- ✅ File system operations
- ✅ Time-dependent functions
- ✅ Random number generators
- ✅ Third-party services

**When NOT to mock**:
- ❌ Internal utility functions
- ❌ Simple calculations
- ❌ Pure functions
- ❌ Data transformations

```typescript
import { describe, it, expect, vi } from 'vitest';

// ✅ GOOD: Mock external API
const mockFetch = vi.fn();
global.fetch = mockFetch;

it('fetches user data', async () => {
  mockFetch.mockResolvedValue({
    ok: true,
    json: async () => ({ id: '1', name: 'John' })
  });

  const user = await fetchUser('1');
  expect(user.name).toBe('John');
});

// ✅ GOOD: Mock time-dependent function
vi.useFakeTimers();
it('expires after 1 hour', () => {
  const token = createToken();
  vi.advanceTimersByTime(3600000); // 1 hour
  expect(token.isExpired()).toBe(true);
});
```

### Test Fixtures

**Use test fixtures for consistent data**:

```typescript
// fixtures/users.ts
export const testUsers = {
  admin: {
    id: '1',
    email: 'admin@example.com',
    role: 'admin' as const
  },
  user: {
    id: '2',
    email: 'user@example.com',
    role: 'user' as const
  },
  guest: {
    id: '3',
    email: 'guest@example.com',
    role: 'guest' as const
  }
};

// test file
import { testUsers } from './fixtures/users';

describe('UserPermissions', () => {
  it('allows admin to delete users', () => {
    const permissions = new UserPermissions(testUsers.admin);
    expect(permissions.canDelete()).toBe(true);
  });

  it('prevents regular user from deleting', () => {
    const permissions = new UserPermissions(testUsers.user);
    expect(permissions.canDelete()).toBe(false);
  });
});
```

### Coverage Goals

**Aim for 80%+ test coverage**:

**What to measure**:
- Line coverage: Percentage of lines executed
- Branch coverage: Percentage of branches taken
- Function coverage: Percentage of functions called

**Check coverage**:
```bash
# Run tests with coverage
Bash: npm test -- --coverage

# Generate coverage report
Bash: npm test -- --coverage --reporter=html

# View coverage report
Read: coverage/index.html
```

**Coverage targets**:
- Critical business logic: 90-100%
- Utility functions: 80-90%
- UI components: 70-80%
- Configuration/setup: 50-70%

**Remember**: High coverage doesn't guarantee quality tests. Focus on meaningful tests, not just hitting coverage targets.

---

## Deployment & Infrastructure

### Generic Deployment Workflow

**Standard deployment process** (adapt to your platform):

1. **Local verification**
   ```bash
   Bash: npm run build
   Bash: npm test
   Bash: npm run lint
   ```

2. **Environment variable check**
   ```bash
   Read: .env.example
   # Verify all required variables are set in deployment platform
   ```

3. **Deploy to staging/preview**
   ```bash
   # Platform-specific command
   Bash: vercel  # Vercel
   Bash: netlify deploy  # Netlify
   Bash: railway up  # Railway
   ```

4. **Validate staging deployment**
   - Test critical user flows
   - Verify API integrations
   - Check error handling
   - Validate environment variables

5. **Deploy to production**
   ```bash
   # Platform-specific command
   Bash: vercel --prod
   Bash: netlify deploy --prod
   Bash: railway up --environment production
   ```

6. **Post-deployment verification**
   - Smoke test critical paths
   - Monitor error logs
   - Check performance metrics
   - Verify health checks

### Environment Variable Management

**Best practices for environment variables**:

**Structure**:
```bash
# .env.example (committed to git)
DATABASE_URL=postgresql://localhost:5432/mydb
API_KEY=your_api_key_here
NODE_ENV=development

# .env (NOT committed, in .gitignore)
DATABASE_URL=postgresql://user:pass@prod.example.com:5432/mydb
API_KEY=prod_key_abc123xyz
NODE_ENV=production
```

**Naming conventions**:
- Use `UPPER_SNAKE_CASE`
- Prefix by category (`DB_`, `API_`, `AWS_`)
- Be descriptive and unambiguous

**Platform-specific commands**:
```bash
# Vercel
Bash: vercel env ls
Bash: vercel env add API_KEY production
Bash: vercel env pull

# Netlify
Bash: netlify env:list
Bash: netlify env:set API_KEY value

# Heroku
Bash: heroku config
Bash: heroku config:set API_KEY=value

# Railway
Bash: railway variables
Bash: railway variables set API_KEY=value
```

### Pre-Deployment Verification

**Checklist before deploying**:

- [ ] All tests passing locally
- [ ] Build succeeds without errors
- [ ] Linting passes
- [ ] Type checking passes (if applicable)
- [ ] Dependencies up to date (security patches)
- [ ] Environment variables documented
- [ ] Database migrations ready (if applicable)
- [ ] Rollback plan prepared
- [ ] Monitoring/alerts configured

**Verification commands**:
```bash
# Full build and test
Bash: npm run build && npm test && npm run lint

# Check for outdated dependencies
Bash: npm outdated

# Security audit
Bash: npm audit

# Bundle size check
Bash: npm run build
Grep: "dist/.*\\.js" --output_mode files_with_matches
# Review bundle sizes
```

### Post-Deployment Validation

**After deployment, verify**:

1. **Health check**
   ```bash
   Bash: curl https://your-app.com/health
   ```

2. **Critical paths**
   - User authentication
   - Core business functions
   - API endpoints
   - Database connections

3. **Error monitoring**
   - Check error tracking (Sentry, Rollbar)
   - Review application logs
   - Monitor performance metrics

4. **Performance**
   - Page load times
   - API response times
   - Resource usage

**Monitoring commands**:
```bash
# View recent logs (platform-specific)
Bash: vercel logs
Bash: netlify logs
Bash: heroku logs --tail

# Check deployment status
Bash: vercel inspect <deployment-url>
```

### Rollback Strategy

**Always have a rollback plan**:

**Preparation**:
- Keep previous version deployable
- Document rollback procedure
- Test rollback in staging
- Have database backup/migration rollback

**Rollback steps**:
```bash
# Platform-specific rollback commands

# Vercel - redeploy previous version
Bash: vercel rollback

# Netlify - restore previous deploy
Bash: netlify rollback

# Heroku - rollback release
Bash: heroku rollback

# Manual - redeploy previous commit
Bash: git checkout <previous-commit>
Bash: <deploy-command>
```

**When to rollback**:
- Critical bugs in production
- Performance degradation
- Security vulnerabilities
- Data integrity issues
- Failed deployment verification

---

## Quality Checklist

### Pre-Commit Checks

**Before committing code**:

- [ ] Code compiles/builds successfully
- [ ] All tests pass
- [ ] Linting rules satisfied
- [ ] Code formatted consistently
- [ ] No debug statements (console.log, debugger, etc.)
- [ ] No commented-out code blocks
- [ ] Type checking passes (if applicable)
- [ ] No hardcoded secrets or credentials

**Pre-commit commands**:
```bash
# Format code
Bash: npm run format
# or
Bash: prettier --write "src/**/*.{ts,tsx,js,jsx}"

# Lint code
Bash: npm run lint -- --fix

# Type check (TypeScript)
Bash: tsc --noEmit

# Run tests
Bash: npm test
```

### Build Verification

**Verify build succeeds**:

```bash
# Clean build
Bash: rm -rf dist/ build/ .next/
Bash: npm run build

# Check build output
Glob: "dist/**/*"
Glob: "build/**/*"

# Verify bundle sizes
Bash: npm run build -- --analyze  # if available
```

**Build checks**:
- [ ] Build completes without errors
- [ ] No build warnings (or documented/approved)
- [ ] Bundle size within acceptable limits
- [ ] Source maps generated (production)
- [ ] Assets optimized (images, fonts)

### Linting and Formatting

**Consistent code style**:

```bash
# Check formatting
Bash: prettier --check "src/**/*.{ts,tsx,js,jsx}"

# Fix formatting
Bash: prettier --write "src/**/*.{ts,tsx,js,jsx}"

# Run linter
Bash: npm run lint

# Fix linting issues
Bash: npm run lint -- --fix
```

**Linting checks**:
- [ ] No linting errors
- [ ] Warnings reviewed and justified
- [ ] Consistent code style
- [ ] Import order correct
- [ ] Unused imports removed

### Test Execution

**Run comprehensive tests**:

```bash
# Run all tests
Bash: npm test

# Run tests with coverage
Bash: npm test -- --coverage

# Run specific test file
Bash: npm test -- path/to/file.test.ts

# Run tests in watch mode (development)
Bash: npm test -- --watch
```

**Test checks**:
- [ ] All tests pass
- [ ] No skipped tests (without justification)
- [ ] Coverage meets targets (80%+)
- [ ] No flaky tests
- [ ] Test names are descriptive
- [ ] Tests follow AAA pattern

### Accessibility Testing

**Ensure accessible code**:

**Automated testing**:
```bash
# Run accessibility tests (if configured)
Bash: npm run test:a11y

# Lighthouse audit
Bash: npm run build
Bash: npx lighthouse http://localhost:3000 --view
```

**Manual testing**:
- [ ] Keyboard navigation works
- [ ] Screen reader compatible
- [ ] Sufficient color contrast
- [ ] Focus indicators visible
- [ ] Semantic HTML used
- [ ] ARIA labels where needed
- [ ] Images have alt text
- [ ] Forms have labels

**Tools**:
- Browser DevTools Lighthouse
- axe DevTools extension
- WAVE browser extension
- Screen readers (NVDA, VoiceOver)

### Error State Handling

**Verify error handling**:

- [ ] User-facing errors have clear messages
- [ ] Errors logged appropriately
- [ ] Error boundaries implemented (React)
- [ ] Network errors handled gracefully
- [ ] Validation errors displayed clearly
- [ ] Fallback UI for critical errors
- [ ] Error recovery flows tested

**Test error scenarios**:
```bash
# Simulate network errors
# (Use browser DevTools network throttling)

# Test validation errors
# (Submit forms with invalid data)

# Test edge cases
# (Empty states, null values, missing data)
```

### Responsive Design

**Verify responsive layout**:

- [ ] Mobile (320px - 768px)
- [ ] Tablet (768px - 1024px)
- [ ] Desktop (1024px+)
- [ ] Large screens (1440px+)

**Testing**:
- Browser DevTools responsive mode
- Real devices (iOS, Android)
- Different orientations
- Touch interactions

**Checks**:
- [ ] Text readable at all sizes
- [ ] Buttons/links large enough for touch
- [ ] Images scale properly
- [ ] Horizontal scrolling avoided
- [ ] Navigation accessible on mobile

### Documentation Updates

**Keep documentation current**:

- [ ] README updated (if needed)
- [ ] API documentation updated
- [ ] Inline code comments added
- [ ] CHANGELOG updated
- [ ] Migration guide written (breaking changes)
- [ ] Configuration examples updated

**Documentation locations**:
```bash
# Check what needs updating
Read: README.md
Read: CHANGELOG.md
Read: docs/API.md

# Update inline documentation (JSDoc, docstrings)
Edit: src/utils/myFunction.ts
```

---

## Appendix

### Tool Migration Reference

**For developers migrating from Cursor to Claude Code**:

| Cursor Tool | Claude Code Tool | Notes |
|------------|------------------|-------|
| `list_dir` | `Bash` (ls) or `Glob` | Use `Glob` for pattern matching |
| `file_search` | `Glob` | Pattern-based file finding |
| `grep_search` | `Grep` | Content search with regex support |
| `codebase_search` | `Grep` | Use with appropriate patterns |
| `read_file` | `Read` | Direct file reading |
| `write_to_file` | `Write` | File creation/overwriting |
| `apply_diff` | `Edit` | Surgical edits to existing files |

### Common Patterns

**Find files by pattern**:
```bash
# Cursor
file_search: "*.test.ts"

# Claude Code
Glob: "**/*.test.ts"
```

**Search file contents**:
```bash
# Cursor
grep_search: "function myFunction"

# Claude Code
Grep: "function myFunction" --output_mode content
```

**Read configuration**:
```bash
# Cursor
read_file: package.json

# Claude Code
Read: /absolute/path/to/package.json
```

### Best Practices Summary

**Development**:
- ✅ Verify before presenting
- ✅ Deep understanding before coding
- ✅ Resolve ambiguities autonomously
- ✅ Make changes file-by-file
- ✅ Preserve existing code
- ✅ Use explicit variable names
- ✅ Prioritize performance and security

**Testing**:
- ✅ Follow AAA pattern
- ✅ Write descriptive test names
- ✅ Keep tests isolated
- ✅ Aim for 80%+ coverage
- ✅ Test edge cases and errors

**Git**:
- ✅ Use conventional commits
- ✅ Make atomic, focused commits
- ✅ Write clear commit messages
- ✅ Follow git safety protocol
- ✅ Never commit secrets

**Quality**:
- ✅ All tests pass
- ✅ Build succeeds
- ✅ Linting passes
- ✅ Accessibility verified
- ✅ Documentation updated
- ✅ Error states handled
- ✅ Responsive design tested

---

## Contributing

This documentation is meant to evolve with your team's practices. When you discover better patterns or workflows:

1. Document the improvement
2. Share with the team
3. Update this guide
4. Commit the changes

**Keep this guide**:
- ✅ Practical and actionable
- ✅ Tool-agnostic where possible
- ✅ Updated with real examples
- ✅ Focused on principles over specifics

---

**Philosophy**: Write code for humans first, computers second. Prioritize clarity, maintainability, and type safety over cleverness.

**Remember**: These are guidelines, not rigid rules. Use judgment and adapt to your specific context, team, and project requirements.

---

**Last Updated**: 2026-01-21
**Maintained By**: Development Team
**License**: Adapt freely for your projects
