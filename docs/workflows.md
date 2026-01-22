# Development Workflows

> Practical, step-by-step workflows for common development tasks with Claude Code

**Version**: 1.0.0
**Last Updated**: 2026-01-21

---

## Table of Contents

1. [Atomic Commit Workflow](#1-atomic-commit-workflow)
2. [Feature Development Workflow](#2-feature-development-workflow)
3. [Test-Driven Development Pattern](#3-test-driven-development-pattern)
4. [Code Review Preparation](#4-code-review-preparation)
5. [Debugging Investigation Workflow](#5-debugging-investigation-workflow)
6. [Safe Refactoring Pattern](#6-safe-refactoring-pattern)
7. [WSL-Specific Considerations](#wsl-specific-considerations)

---

## 1. Atomic Commit Workflow

### When to Use

- Making any code changes, no matter how small
- Want clear, reviewable history
- Need ability to easily revert changes
- Following conventional commits standard

### Prerequisites

- Working git repository
- Changes ready to commit
- Understanding of what changed and why

### Step-by-Step Process

#### Step 1: Review What Changed

```bash
# Check current status
git status

# Review unstaged changes
git diff

# Review staged changes
git diff --cached
```

**Claude Code approach:**
```bash
Bash: git status
Bash: git diff
```

**What to look for:**
- Are changes focused on ONE logical change?
- Any unintended modifications?
- Any debug code (console.log, debugger) to remove?
- Any commented-out code to clean up?

#### Step 2: Verify Changes Work

```bash
# Run tests
npm test

# Run linter
npm run lint

# Build (if applicable)
npm run build

# Type check (TypeScript)
npx tsc --noEmit
```

**Claude Code approach:**
```bash
Bash: npm test && npm run lint && npm run build
```

**Verification checklist:**
- [ ] All tests pass
- [ ] No linting errors
- [ ] Build succeeds
- [ ] Type checking passes
- [ ] Code runs as expected

#### Step 3: Stage Files Strategically

**Anti-pattern: Stage everything**
```bash
# ❌ BAD - Stages everything including unintended files
git add -A
git add .
```

**Best practice: Stage specific files**
```bash
# ✅ GOOD - Stage only files for this logical change
git add src/components/Button.tsx
git add src/components/Button.module.css
```

**Claude Code approach:**
```bash
Bash: git add src/components/Button.tsx src/components/Button.module.css
```

**Grouping rules:**
- **Ideal:** Single file
- **Acceptable:** Component + styles (inseparable)
- **Acceptable:** Component + test (related)
- **Maximum:** Component + styles + test
- **Never:** Multiple unrelated files

#### Step 4: Write Descriptive Commit Message

**Format:**
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code refactoring (no functional change)
- `test`: Adding/updating tests
- `docs`: Documentation changes
- `style`: Code formatting (not CSS)
- `perf`: Performance improvements
- `chore`: Maintenance tasks
- `a11y`: Accessibility improvements

**Examples:**
```bash
# Simple feature
git commit -m "feat: add primary button variant"

# Bug fix with context
git commit -m "fix: resolve race condition in form submission

The form was submitting multiple times when user clicked rapidly.
Added debounce to prevent duplicate submissions.

Closes #123"

# Refactoring
git commit -m "refactor: extract validation logic to utils"

# Test addition
git commit -m "test: add coverage for edge cases in formatDate"
```

**Claude Code approach:**
```bash
Bash: git commit -m "feat: add primary button variant"
```

#### Step 5: Verify Commit

```bash
# View commit details
git show HEAD

# View commit in log
git log -1 --stat
```

**Claude Code approach:**
```bash
Bash: git show HEAD
Bash: git log -1 --stat
```

**Verify:**
- [ ] Correct files included
- [ ] Clear, descriptive message
- [ ] No unintended changes
- [ ] Commit is atomic (one logical change)

### Example Walkthrough

**Scenario:** Adding email validation to a user registration form

```bash
# Step 1: Review changes
Bash: git status
# Shows: src/utils/validation.ts (modified)

Bash: git diff
# Review: Added validateEmail function

# Step 2: Verify changes work
Bash: npm test -- src/utils/validation.test.ts
# All tests pass

# Step 3: Stage specific file
Bash: git add src/utils/validation.ts

# Step 4: Commit with descriptive message
Bash: git commit -m "feat: add email validation function

Validates email format using RFC 5322 regex.
Returns boolean indicating validity."

# Step 5: Verify commit
Bash: git show HEAD
# Looks good!

# Continue with next logical change (test file)
Bash: git add src/utils/validation.test.ts
Bash: git commit -m "test: add email validation test coverage"
```

### Common Pitfalls

**Pitfall 1: Commits too large**
- **Problem:** Changed 10 files in one commit
- **Solution:** Break into multiple commits, one per logical change
- **Example:** Separate "add feature" from "add tests" from "update docs"

**Pitfall 2: Unclear commit messages**
- **Problem:** `git commit -m "updates"` or `git commit -m "fix stuff"`
- **Solution:** Use conventional commits format with descriptive message
- **Example:** `git commit -m "fix: resolve memory leak in event listeners"`

**Pitfall 3: Mixing unrelated changes**
- **Problem:** Bug fix + new feature + refactoring in one commit
- **Solution:** Separate into three commits
- **Example:**
  - Commit 1: `fix: resolve null pointer exception`
  - Commit 2: `feat: add export to CSV feature`
  - Commit 3: `refactor: extract CSV logic to utils`

**Pitfall 4: Including debug code**
- **Problem:** Committed `console.log` statements
- **Solution:** Review diff carefully, remove debug code before committing
- **Check:** Search for `console.log`, `debugger`, `TODO`, `FIXME`

**Pitfall 5: Staging with `git add -A`**
- **Problem:** Accidentally staged `.env`, `node_modules`, or other unintended files
- **Solution:** Always stage specific files by name
- **Extra safety:** Review `git status` and `git diff --cached` before committing

### Tips for Success

1. **Commit early, commit often:** Don't wait until end of day
2. **Read the diff:** Always review what you're committing
3. **One logical change:** If you can't describe it in one sentence, it's too big
4. **Think about reverting:** Could you easily revert this commit if needed?
5. **Consider git bisect:** Would this commit help locate bugs later?
6. **Test before commit:** Every commit should work and pass tests
7. **Meaningful messages:** Future you will thank you for clear messages

### Tools & Commands Reference

```bash
# Review changes
git status                    # See what changed
git diff                      # Unstaged changes
git diff --cached             # Staged changes
git log --oneline -10         # Recent commits

# Stage changes
git add <file>                # Stage specific file
git add -p                    # Stage interactively (review each hunk)
git reset <file>              # Unstage file

# Commit
git commit -m "message"       # Commit with message
git commit --amend            # Amend last commit (if not pushed)
git commit --no-verify        # Skip pre-commit hooks (use sparingly)

# Review commits
git show HEAD                 # Show last commit
git log -1 --stat             # Last commit with file stats
git log --oneline --graph     # Visual commit history

# Undo commits (local only)
git reset --soft HEAD~1       # Undo commit, keep changes staged
git reset HEAD~1              # Undo commit, keep changes unstaged
git reset --hard HEAD~1       # Undo commit, discard changes (DANGEROUS)
```

---

## 2. Feature Development Workflow

### When to Use

- Developing a new feature
- Making breaking changes
- Working on something that takes multiple commits
- Need isolated development from main branch

### Prerequisites

- Clean working directory (`git status` shows no changes)
- Up-to-date main branch
- Clear understanding of feature requirements
- Access to remote repository

### Step-by-Step Process

#### Step 1: Ensure Clean Starting Point

```bash
# Save any work in progress
git stash

# Switch to main branch
git checkout main

# Pull latest changes
git pull origin main --no-edit

# Verify clean state
git status
```

**Claude Code approach:**
```bash
Bash: git stash
Bash: git checkout main && git pull origin main --no-edit
Bash: git status
```

**WSL Note:** Git operations are faster in native WSL filesystem (`/home/...`) vs Windows filesystem (`/mnt/c/...`)

#### Step 2: Create Feature Branch

**Naming convention:**
```
<type>/<ticket-id>-<short-description>

Examples:
feature/123-add-user-authentication
fix/456-resolve-memory-leak
refactor/789-extract-api-client
```

```bash
# Create and switch to new branch
git checkout -b feature/123-add-user-authentication

# Verify branch created
git branch --show-current
```

**Claude Code approach:**
```bash
Bash: git checkout -b feature/123-add-user-authentication
Bash: git branch --show-current
```

#### Step 3: Plan Your Implementation

**Before writing code, investigate:**

```bash
# Find similar implementations
Glob: "**/*auth*"
Grep: "authentication" --output_mode files_with_matches

# Understand existing patterns
Read: /path/to/existing-auth-file.ts
Grep: "login|signup|auth" --output_mode content

# Check project structure
Bash: ls -la src/
Glob: "**/*.test.ts"  # Find test patterns

# Review documentation
Read: /README.md
Read: /docs/architecture.md
```

**Planning checklist:**
- [ ] Understand existing patterns
- [ ] Identify affected files
- [ ] Plan test strategy
- [ ] Consider edge cases
- [ ] Check for dependencies

#### Step 4: Implement in Small Increments

**Follow incremental commit pattern:**

**Increment 1: Type definitions / Interfaces**
```bash
# Create/modify types
Edit: src/types/auth.ts

# Verify
Bash: npx tsc --noEmit

# Commit
Bash: git add src/types/auth.ts
Bash: git commit -m "feat: add authentication type definitions"
```

**Increment 2: Core implementation**
```bash
# Implement main logic
Edit: src/auth/AuthProvider.tsx

# Verify
Bash: npm run build

# Commit
Bash: git add src/auth/AuthProvider.tsx
Bash: git commit -m "feat: implement AuthProvider component"
```

**Increment 3: Tests**
```bash
# Write tests
Edit: src/auth/AuthProvider.test.tsx

# Run tests
Bash: npm test -- src/auth/AuthProvider.test.tsx

# Commit
Bash: git add src/auth/AuthProvider.test.tsx
Bash: git commit -m "test: add AuthProvider test coverage"
```

**Increment 4: Integration**
```bash
# Integrate into app
Edit: src/App.tsx

# Test integration
Bash: npm run dev  # Manual verification

# Commit
Bash: git add src/App.tsx
Bash: git commit -m "feat: integrate AuthProvider into app"
```

**Increment 5: Documentation**
```bash
# Update docs
Edit: README.md

# Commit
Bash: git add README.md
Bash: git commit -m "docs: document authentication setup"
```

#### Step 5: Comprehensive Testing

```bash
# Run all tests
npm test

# Check coverage
npm test -- --coverage

# Run linter
npm run lint

# Type check
npx tsc --noEmit

# Build
npm run build

# Manual testing
npm run dev
```

**Claude Code approach:**
```bash
Bash: npm test -- --coverage
Bash: npm run lint && npx tsc --noEmit && npm run build
```

**Testing checklist:**
- [ ] All tests pass
- [ ] Coverage ≥ 80% for new code
- [ ] Linting passes
- [ ] Type checking passes
- [ ] Build succeeds
- [ ] Manual testing complete
- [ ] Edge cases tested
- [ ] Error handling verified

#### Step 6: Push to Remote

```bash
# Push branch to remote
git push -u origin feature/123-add-user-authentication

# Verify push
git status
```

**Claude Code approach:**
```bash
Bash: git push -u origin feature/123-add-user-authentication
Bash: git status
```

**WSL Note:** If using SSH keys, ensure they're configured in WSL environment, not Windows.

#### Step 7: Create Pull Request

**Option 1: Using GitHub CLI (recommended)**
```bash
# Create PR with title and body
gh pr create --title "Add user authentication" --body "Implements user authentication with email/password.

## Changes
- Added AuthProvider component
- Implemented login/logout functionality
- Added session management
- Added comprehensive tests

## Testing
- All tests passing
- 85% coverage for new code
- Manual testing complete

Closes #123"
```

**Claude Code approach:**
```bash
Bash: gh pr create --title "Add user authentication" --body "$(cat <<'EOF'
Implements user authentication with email/password.

## Changes
- Added AuthProvider component
- Implemented login/logout functionality
- Added session management
- Added comprehensive tests

## Testing
- All tests passing
- 85% coverage for new code
- Manual testing complete

Closes #123
EOF
)"
```

**Option 2: Using Web Interface**
1. Visit repository on GitHub
2. Click "Pull requests" → "New pull request"
3. Select your branch
4. Fill in title and description
5. Request reviewers
6. Create pull request

#### Step 8: Address Review Feedback

```bash
# Make requested changes
Edit: src/auth/AuthProvider.tsx

# Test changes
Bash: npm test

# Commit changes
Bash: git add src/auth/AuthProvider.tsx
Bash: git commit -m "fix: address review feedback on error handling"

# Push updates
Bash: git push origin feature/123-add-user-authentication
```

**Note:** PR automatically updates with new commits

#### Step 9: Merge and Cleanup

After PR approval:

```bash
# Merge via GitHub UI or CLI
gh pr merge 123 --squash  # or --merge or --rebase

# Switch back to main
git checkout main

# Pull merged changes
git pull origin main --no-edit

# Delete local feature branch
git branch -d feature/123-add-user-authentication

# Delete remote branch (if not auto-deleted)
git push origin --delete feature/123-add-user-authentication
```

**Claude Code approach:**
```bash
Bash: gh pr merge 123 --squash
Bash: git checkout main && git pull origin main --no-edit
Bash: git branch -d feature/123-add-user-authentication
```

### Example Walkthrough

**Scenario:** Add export to CSV feature

```bash
# Step 1: Clean starting point
Bash: git checkout main && git pull origin main --no-edit
Bash: git status

# Step 2: Create feature branch
Bash: git checkout -b feature/456-add-csv-export
Bash: git branch --show-current

# Step 3: Research existing code
Grep: "export.*download" --output_mode files_with_matches
Read: /src/utils/download.ts
Glob: "**/*export*"

# Step 4: Implement incrementally

# Increment 1: CSV utility function
Edit: src/utils/csv.ts
Bash: npx tsc --noEmit
Bash: git add src/utils/csv.ts
Bash: git commit -m "feat: add CSV generation utility"

# Increment 2: Tests for CSV utility
Edit: src/utils/csv.test.ts
Bash: npm test -- src/utils/csv.test.ts
Bash: git add src/utils/csv.test.ts
Bash: git commit -m "test: add CSV utility test coverage"

# Increment 3: Export button component
Edit: src/components/ExportButton.tsx
Bash: npm run build
Bash: git add src/components/ExportButton.tsx
Bash: git commit -m "feat: add ExportButton component"

# Increment 4: Integration
Edit: src/pages/Dashboard.tsx
Bash: npm run dev  # Manual test
Bash: git add src/pages/Dashboard.tsx
Bash: git commit -m "feat: integrate CSV export in Dashboard"

# Step 5: Comprehensive testing
Bash: npm test -- --coverage
Bash: npm run lint && npm run build

# Step 6: Push to remote
Bash: git push -u origin feature/456-add-csv-export

# Step 7: Create PR
Bash: gh pr create --title "Add CSV export feature" --body "$(cat <<'EOF'
## Summary
Adds CSV export functionality to dashboard data table.

## Changes
- CSV generation utility with proper escaping
- ExportButton component with download trigger
- Integration in Dashboard page
- Comprehensive test coverage

## Testing
- Unit tests for CSV generation
- Component tests for ExportButton
- Manual testing with various data sets
- Edge cases: empty data, special characters, large datasets

## Screenshots
[Include screenshots if applicable]

Closes #456
EOF
)"
```

### Common Pitfalls

**Pitfall 1: Long-lived feature branches**
- **Problem:** Branch diverges significantly from main
- **Solution:** Regularly merge main into feature branch
- **Command:** `git merge main` or `git rebase main`

**Pitfall 2: Skipping tests**
- **Problem:** "I'll add tests later" → tests never added
- **Solution:** Write tests as you go, include in same PR
- **Best practice:** Test-driven development (see TDD workflow)

**Pitfall 3: Massive PRs**
- **Problem:** 50 files changed, impossible to review
- **Solution:** Break into smaller PRs, feature flags for partial features
- **Guideline:** Keep PRs under 400 lines changed

**Pitfall 4: Unclear PR description**
- **Problem:** "Added stuff" or "Updates"
- **Solution:** Include what, why, testing done, screenshots
- **Template:** What changed, why it changed, how to test

**Pitfall 5: Not updating main first**
- **Problem:** Feature branch based on outdated main
- **Solution:** Always pull main before creating feature branch
- **Command:** `git checkout main && git pull origin main`

### Tips for Success

1. **Small PRs:** Easier to review, faster to merge
2. **Frequent commits:** Checkpoint progress, easier to undo
3. **Descriptive branch names:** Clear what feature is being worked on
4. **Test continuously:** Don't wait until end to run tests
5. **Document as you go:** Update docs with code changes
6. **Review your own PR:** Catch issues before reviewers do
7. **Responsive to feedback:** Address comments promptly
8. **Keep branch updated:** Regularly merge/rebase from main

### Tools & Commands Reference

```bash
# Branch management
git branch                              # List branches
git branch --show-current               # Current branch name
git checkout -b feature/name            # Create and switch to branch
git checkout main                       # Switch to main
git branch -d feature/name              # Delete local branch
git push origin --delete feature/name   # Delete remote branch

# Remote operations
git push -u origin feature/name         # Push and set upstream
git push                                # Push to upstream
git pull origin main --no-edit          # Pull without merge commit

# GitHub CLI (gh)
gh pr create                            # Create PR interactively
gh pr create --title "..." --body "..." # Create PR with details
gh pr list                              # List PRs
gh pr view 123                          # View PR details
gh pr merge 123 --squash                # Merge PR

# Keeping branch updated
git merge main                          # Merge main into feature
git rebase main                         # Rebase feature on main
```

---

## 3. Test-Driven Development Pattern

### When to Use

- Implementing complex business logic
- Building critical features
- Refactoring existing code
- Want to ensure comprehensive test coverage
- Clear requirements known upfront

### Prerequisites

- Test framework configured (Jest, Vitest, pytest, etc.)
- Understanding of feature requirements
- Familiarity with testing patterns

### Step-by-Step Process

#### Step 1: Write Failing Test

**Before writing any implementation code, write the test:**

```typescript
// src/utils/calculateDiscount.test.ts
import { describe, it, expect } from 'vitest';
import { calculateDiscount } from './calculateDiscount';

describe('calculateDiscount', () => {
  it('applies 10% discount for orders over $100', () => {
    // Arrange
    const orderTotal = 150;
    const discountRate = 0.10;

    // Act
    const result = calculateDiscount(orderTotal, discountRate);

    // Assert
    expect(result).toBe(15); // 150 * 0.10 = 15
  });
});
```

**Claude Code approach:**
```bash
Write: src/utils/calculateDiscount.test.ts
```

#### Step 2: Run Test (Should Fail)

```bash
# Run the test - it should fail
npm test -- src/utils/calculateDiscount.test.ts
```

**Expected output:**
```
❌ FAIL  src/utils/calculateDiscount.test.ts
  ● calculateDiscount › applies 10% discount for orders over $100
    Cannot find module './calculateDiscount'
```

**Claude Code approach:**
```bash
Bash: npm test -- src/utils/calculateDiscount.test.ts
```

**Why this matters:** Confirms test is actually running and testing the right thing.

#### Step 3: Write Minimal Implementation

**Write just enough code to make the test pass:**

```typescript
// src/utils/calculateDiscount.ts
export function calculateDiscount(
  orderTotal: number,
  discountRate: number
): number {
  return orderTotal * discountRate;
}
```

**Claude Code approach:**
```bash
Write: src/utils/calculateDiscount.ts
```

**Principle:** Don't over-engineer. Solve the immediate test case.

#### Step 4: Run Test (Should Pass)

```bash
# Run the test - it should pass now
npm test -- src/utils/calculateDiscount.test.ts
```

**Expected output:**
```
✓ PASS  src/utils/calculateDiscount.test.ts
  ✓ calculateDiscount › applies 10% discount for orders over $100 (2ms)
```

**Claude Code approach:**
```bash
Bash: npm test -- src/utils/calculateDiscount.test.ts
```

#### Step 5: Commit

```bash
# Commit the working feature
git add src/utils/calculateDiscount.ts src/utils/calculateDiscount.test.ts
git commit -m "feat: add discount calculation with 10% rate support"
```

**Claude Code approach:**
```bash
Bash: git add src/utils/calculateDiscount.ts src/utils/calculateDiscount.test.ts
Bash: git commit -m "feat: add discount calculation with 10% rate support"
```

**Note:** Both test and implementation in one commit is acceptable for TDD.

#### Step 6: Add Next Test (Edge Case)

```typescript
// src/utils/calculateDiscount.test.ts
describe('calculateDiscount', () => {
  it('applies 10% discount for orders over $100', () => {
    // ... existing test
  });

  it('returns 0 for negative order totals', () => {
    // Arrange
    const orderTotal = -50;
    const discountRate = 0.10;

    // Act
    const result = calculateDiscount(orderTotal, discountRate);

    // Assert
    expect(result).toBe(0);
  });
});
```

**Claude Code approach:**
```bash
Edit: src/utils/calculateDiscount.test.ts
```

#### Step 7: Run Test (Should Fail)

```bash
npm test -- src/utils/calculateDiscount.test.ts
```

**Expected output:**
```
❌ FAIL  src/utils/calculateDiscount.test.ts
  ✓ applies 10% discount for orders over $100
  ✕ returns 0 for negative order totals
    Expected: 0
    Received: -5
```

#### Step 8: Update Implementation

```typescript
// src/utils/calculateDiscount.ts
export function calculateDiscount(
  orderTotal: number,
  discountRate: number
): number {
  // Handle negative order totals
  if (orderTotal < 0) {
    return 0;
  }

  return orderTotal * discountRate;
}
```

**Claude Code approach:**
```bash
Edit: src/utils/calculateDiscount.ts
```

#### Step 9: Run Test (Should Pass)

```bash
npm test -- src/utils/calculateDiscount.test.ts
```

**Expected output:**
```
✓ PASS  src/utils/calculateDiscount.test.ts
  ✓ applies 10% discount for orders over $100
  ✓ returns 0 for negative order totals
```

#### Step 10: Refactor (If Needed)

**Now that tests are passing, improve the code:**

```typescript
// src/utils/calculateDiscount.ts
export function calculateDiscount(
  orderTotal: number,
  discountRate: number
): number {
  // Validate inputs
  if (orderTotal < 0 || discountRate < 0 || discountRate > 1) {
    return 0;
  }

  return orderTotal * discountRate;
}
```

**Run tests to ensure refactoring didn't break anything:**
```bash
npm test -- src/utils/calculateDiscount.test.ts
```

**Claude Code approach:**
```bash
Edit: src/utils/calculateDiscount.ts
Bash: npm test -- src/utils/calculateDiscount.test.ts
```

#### Step 11: Add More Tests

```typescript
describe('calculateDiscount', () => {
  // ... existing tests

  it('returns 0 for invalid discount rates', () => {
    expect(calculateDiscount(100, -0.1)).toBe(0);
    expect(calculateDiscount(100, 1.5)).toBe(0);
  });

  it('handles zero discount rate', () => {
    expect(calculateDiscount(100, 0)).toBe(0);
  });

  it('handles maximum discount rate', () => {
    expect(calculateDiscount(100, 1)).toBe(100);
  });

  it('handles decimal amounts correctly', () => {
    expect(calculateDiscount(99.99, 0.15)).toBeCloseTo(15.00, 2);
  });
});
```

#### Step 12: Commit

```bash
git add src/utils/calculateDiscount.ts src/utils/calculateDiscount.test.ts
git commit -m "feat: add edge case handling for discount calculation"
```

### TDD Cycle Summary

```
Red → Green → Refactor → Repeat

1. RED:     Write failing test
2. GREEN:   Write minimal code to pass
3. REFACTOR: Improve code while keeping tests green
4. REPEAT:  Add next test
```

### Example Walkthrough

**Scenario:** Implement email validation function using TDD

```bash
# Step 1: Write failing test
Write: src/utils/validation.test.ts
```

```typescript
import { describe, it, expect } from 'vitest';
import { isValidEmail } from './validation';

describe('isValidEmail', () => {
  it('returns true for valid email', () => {
    expect(isValidEmail('user@example.com')).toBe(true);
  });
});
```

```bash
# Step 2: Run test (should fail)
Bash: npm test -- src/utils/validation.test.ts
# Output: Cannot find module './validation'

# Step 3: Write minimal implementation
Write: src/utils/validation.ts
```

```typescript
export function isValidEmail(email: string): boolean {
  return true; // Simplest code to make test pass
}
```

```bash
# Step 4: Run test (should pass)
Bash: npm test -- src/utils/validation.test.ts
# Output: ✓ PASS

# Step 5: Commit
Bash: git add src/utils/validation.ts src/utils/validation.test.ts
Bash: git commit -m "feat: add basic email validation"

# Step 6: Add test for invalid email
Edit: src/utils/validation.test.ts
```

```typescript
describe('isValidEmail', () => {
  it('returns true for valid email', () => {
    expect(isValidEmail('user@example.com')).toBe(true);
  });

  it('returns false for invalid email without @', () => {
    expect(isValidEmail('userexample.com')).toBe(false);
  });
});
```

```bash
# Step 7: Run test (should fail)
Bash: npm test -- src/utils/validation.test.ts
# Output: Expected false, received true

# Step 8: Update implementation
Edit: src/utils/validation.ts
```

```typescript
export function isValidEmail(email: string): boolean {
  return email.includes('@');
}
```

```bash
# Step 9: Run test (should pass)
Bash: npm test -- src/utils/validation.test.ts
# Output: ✓ PASS (both tests)

# Step 10: Refactor with proper regex
Edit: src/utils/validation.ts
```

```typescript
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function isValidEmail(email: string): boolean {
  if (!email || typeof email !== 'string') {
    return false;
  }
  return EMAIL_REGEX.test(email);
}
```

```bash
# Verify refactoring didn't break tests
Bash: npm test -- src/utils/validation.test.ts

# Step 11: Add more test cases
Edit: src/utils/validation.test.ts
```

```typescript
describe('isValidEmail', () => {
  it('returns true for valid email', () => {
    expect(isValidEmail('user@example.com')).toBe(true);
    expect(isValidEmail('test.user@sub.example.co.uk')).toBe(true);
  });

  it('returns false for invalid email without @', () => {
    expect(isValidEmail('userexample.com')).toBe(false);
  });

  it('returns false for email without domain', () => {
    expect(isValidEmail('user@')).toBe(false);
  });

  it('returns false for empty string', () => {
    expect(isValidEmail('')).toBe(false);
  });

  it('returns false for null/undefined', () => {
    expect(isValidEmail(null as any)).toBe(false);
    expect(isValidEmail(undefined as any)).toBe(false);
  });
});
```

```bash
# Run all tests
Bash: npm test -- src/utils/validation.test.ts

# Step 12: Final commit
Bash: git add src/utils/validation.ts src/utils/validation.test.ts
Bash: git commit -m "feat: add comprehensive email validation with edge cases"
```

### Common Pitfalls

**Pitfall 1: Writing implementation before test**
- **Problem:** Defeats purpose of TDD
- **Solution:** Discipline - always write test first
- **Benefit:** Ensures testable, focused design

**Pitfall 2: Writing too many tests at once**
- **Problem:** Get overwhelmed, lose focus
- **Solution:** One test at a time, make it pass, then next
- **Cycle:** Red → Green → Refactor → Repeat

**Pitfall 3: Not running tests frequently**
- **Problem:** Don't know if code works
- **Solution:** Run tests after every change
- **Tool:** Use watch mode: `npm test -- --watch`

**Pitfall 4: Testing implementation details**
- **Problem:** Tests break when refactoring
- **Solution:** Test behavior, not implementation
- **Example:** Test "returns discount amount" not "calls calculateDiscount internally"

**Pitfall 5: Skipping refactoring step**
- **Problem:** Code becomes messy over time
- **Solution:** After tests pass, clean up code
- **Safety:** Tests ensure refactoring doesn't break functionality

### Tips for Success

1. **Baby steps:** Make smallest possible change to pass test
2. **One test at a time:** Don't write multiple tests before implementing
3. **Run frequently:** Run tests after every change
4. **Refactor confidently:** Tests are your safety net
5. **Test behavior:** Focus on what code does, not how
6. **Clear test names:** Should read like documentation
7. **AAA pattern:** Arrange, Act, Assert - every test
8. **Keep tests fast:** Fast tests = run more often

### TDD Benefits

- **Design:** Forces you to think about API before implementation
- **Coverage:** Naturally achieves high test coverage
- **Confidence:** Tests provide safety net for refactoring
- **Documentation:** Tests document how code should behave
- **Debugging:** Easier to find bugs (last test added)
- **Quality:** Results in more modular, testable code

### Tools & Commands Reference

```bash
# Run specific test file
npm test -- path/to/file.test.ts
npm test -- src/utils/validation.test.ts

# Run tests in watch mode
npm test -- --watch
npm test -- --watch src/utils/

# Run tests with coverage
npm test -- --coverage
npm test -- --coverage src/utils/

# Run only tests matching pattern
npm test -- --grep "email"
npm test -- -t "validation"

# Run tests for changed files
npm test -- --onlyChanged
```

---

## 4. Code Review Preparation

### When to Use

- Before submitting a pull request
- Before requesting code review
- Want to catch issues early
- Ensure PR is reviewer-friendly

### Prerequisites

- Feature/fix complete
- All commits pushed to feature branch
- Ready to create pull request

### Step-by-Step Process

#### Step 1: Self-Review Code Changes

**Review the entire diff:**

```bash
# View all changes in feature branch
git diff main...HEAD

# View changes per commit
git log main..HEAD --oneline
git show <commit-hash>
```

**Claude Code approach:**
```bash
Bash: git diff main...HEAD
Bash: git log main..HEAD --oneline
```

**What to look for:**

**Code quality:**
- [ ] Variable names are descriptive
- [ ] Functions are focused and small
- [ ] No code duplication
- [ ] Comments explain "why", not "what"
- [ ] No commented-out code
- [ ] No debug statements (console.log, debugger)
- [ ] Consistent code style

**Logic:**
- [ ] Edge cases handled
- [ ] Error handling implemented
- [ ] Input validation present
- [ ] No hardcoded values (use constants)
- [ ] Performance considered
- [ ] Security considered

**Tests:**
- [ ] All new code has tests
- [ ] Tests are meaningful (not just for coverage)
- [ ] Edge cases tested
- [ ] Error cases tested
- [ ] Tests follow AAA pattern

**Documentation:**
- [ ] README updated (if needed)
- [ ] API docs updated
- [ ] Inline comments for complex logic
- [ ] Changelog updated

#### Step 2: Run Full Test Suite

```bash
# Run all tests
npm test

# Check coverage
npm test -- --coverage

# Verify coverage meets threshold
cat coverage/coverage-summary.json
```

**Claude Code approach:**
```bash
Bash: npm test -- --coverage
Read: coverage/coverage-summary.json
```

**Coverage checklist:**
- [ ] Overall coverage ≥ 80%
- [ ] New code coverage ≥ 80%
- [ ] Critical paths at 100%
- [ ] No untested error handling

#### Step 3: Verify Build

```bash
# Clean build
rm -rf dist/ build/ .next/
npm run build

# Check for build warnings
# Review bundle size
```

**Claude Code approach:**
```bash
Bash: rm -rf dist/ build/ .next/ && npm run build
```

**Build checklist:**
- [ ] Build completes successfully
- [ ] No build errors
- [ ] Build warnings reviewed and justified
- [ ] Bundle size acceptable
- [ ] No accidental debug code in production build

#### Step 4: Lint and Format

```bash
# Run linter
npm run lint

# Fix auto-fixable issues
npm run lint -- --fix

# Check formatting
npm run format:check

# Fix formatting
npm run format
```

**Claude Code approach:**
```bash
Bash: npm run lint -- --fix
Bash: npm run format
```

**Linting checklist:**
- [ ] No linting errors
- [ ] Warnings reviewed and justified
- [ ] Code formatted consistently
- [ ] Import order correct
- [ ] Unused imports removed
- [ ] TypeScript strict mode satisfied

#### Step 5: Type Checking (TypeScript)

```bash
# Type check
npx tsc --noEmit

# Type check with strict mode
npx tsc --noEmit --strict
```

**Claude Code approach:**
```bash
Bash: npx tsc --noEmit
```

**Type checking checklist:**
- [ ] No type errors
- [ ] No `any` types (except where justified)
- [ ] Proper interface definitions
- [ ] Correct return types
- [ ] Null safety considered

#### Step 6: Manual Testing

**Test critical paths:**
- [ ] Happy path works
- [ ] Error cases handled gracefully
- [ ] Edge cases work correctly
- [ ] UI responsive (if applicable)
- [ ] Accessibility (keyboard navigation, screen reader)
- [ ] Cross-browser (if web)

**Performance testing:**
- [ ] No performance regressions
- [ ] Large data sets handled
- [ ] Loading states present
- [ ] No memory leaks

#### Step 7: Dependency Audit

```bash
# Check for security vulnerabilities
npm audit

# Check for outdated dependencies
npm outdated

# Review dependency changes
git diff main...HEAD -- package.json package-lock.json
```

**Claude Code approach:**
```bash
Bash: npm audit
Bash: npm outdated
Bash: git diff main...HEAD -- package.json
```

**Dependency checklist:**
- [ ] No high/critical vulnerabilities
- [ ] New dependencies justified
- [ ] Dependency versions pinned
- [ ] No unnecessary dependencies
- [ ] License compatibility checked

#### Step 8: Check Commit History

```bash
# Review commit messages
git log main..HEAD

# Check commit structure
git log main..HEAD --oneline --graph
```

**Claude Code approach:**
```bash
Bash: git log main..HEAD --oneline
```

**Commit checklist:**
- [ ] Clear, descriptive messages
- [ ] Conventional commits format
- [ ] Logical commit grouping
- [ ] No "WIP" or "temp" commits
- [ ] Each commit builds successfully
- [ ] Commits tell a story

**Consider squashing if needed:**
```bash
# Interactive rebase to squash commits
git rebase -i main

# Or squash when merging PR
```

#### Step 9: Prepare PR Description

**Template:**

```markdown
## Summary
Brief description of what this PR does and why.

## Changes
- Bullet point list of changes
- Keep it focused and clear
- Group related changes

## Testing
- How was this tested?
- What test cases were covered?
- Any manual testing done?

## Screenshots
[If UI changes, include before/after screenshots]

## Checklist
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] No breaking changes (or documented)
- [ ] Backward compatible

## Additional Notes
Any additional context, decisions made, or things to watch out for.

Closes #<issue-number>
```

**Claude Code approach:**
```bash
# Create comprehensive PR description
# Include all relevant context for reviewers
```

#### Step 10: Final Verification

```bash
# Ensure branch is up to date with main
git fetch origin
git merge origin/main

# Resolve any conflicts
# Run tests again
npm test

# Push final changes
git push origin feature/branch-name
```

**Claude Code approach:**
```bash
Bash: git fetch origin && git merge origin/main
Bash: npm test
Bash: git push origin feature/branch-name
```

**Final checklist:**
- [ ] Branch up to date with main
- [ ] All conflicts resolved
- [ ] Tests still passing
- [ ] Build still succeeds
- [ ] Ready for review

### Example Walkthrough

**Scenario:** Self-review before submitting authentication PR

```bash
# Step 1: Self-review all changes
Bash: git diff main...HEAD > /tmp/review.diff
Read: /tmp/review.diff

# Review findings:
# - Found console.log in AuthProvider.tsx
# - Spotted hardcoded API URL
# - Missing error handling in login function

# Fix issues found
Edit: src/auth/AuthProvider.tsx
# - Remove console.log
# - Move API URL to constants
# - Add try-catch for login

Bash: git add src/auth/AuthProvider.tsx
Bash: git commit -m "fix: remove debug code and improve error handling"

# Step 2: Run full test suite
Bash: npm test -- --coverage

# Output shows 78% coverage on new auth code
# Need to add more tests

Edit: src/auth/AuthProvider.test.tsx
# Add tests for error cases

Bash: npm test -- --coverage
# Coverage now at 85% ✓

Bash: git add src/auth/AuthProvider.test.tsx
Bash: git commit -m "test: add error case coverage for auth"

# Step 3: Verify build
Bash: rm -rf dist/ && npm run build
# Build successful ✓

# Step 4: Lint and format
Bash: npm run lint -- --fix
# Found unused import, fixed automatically

Bash: npm run format
# Formatted 3 files

Bash: git add -A
Bash: git commit -m "style: fix linting and formatting"

# Step 5: Type checking
Bash: npx tsc --noEmit
# All type checks pass ✓

# Step 6: Manual testing
Bash: npm run dev
# Test login flow
# Test logout flow
# Test error cases
# Test session persistence
# All working ✓

# Step 7: Dependency audit
Bash: npm audit
# No vulnerabilities ✓

# Step 8: Check commit history
Bash: git log main..HEAD --oneline
# Output:
# abc1234 style: fix linting and formatting
# def5678 test: add error case coverage for auth
# ghi9012 fix: remove debug code and improve error handling
# jkl3456 feat: add session persistence
# mno7890 test: add auth provider tests
# pqr1234 feat: implement auth provider
# stu5678 feat: add auth type definitions

# Commits look good, tell a clear story ✓

# Step 9: Prepare PR description
# Write comprehensive description with:
# - Summary of authentication feature
# - List of changes
# - Testing approach
# - Screenshots of login/logout flow

# Step 10: Final verification
Bash: git fetch origin && git merge origin/main
# No conflicts ✓

Bash: npm test && npm run build
# All passing ✓

Bash: git push origin feature/123-add-user-authentication

# Create PR with prepared description
Bash: gh pr create --title "Add user authentication" --body "..."
```

### Common Pitfalls

**Pitfall 1: Skipping self-review**
- **Problem:** Submit PR with obvious issues
- **Solution:** Always review your own diff first
- **Benefit:** Catch embarrassing mistakes before others see them

**Pitfall 2: Not testing edge cases**
- **Problem:** Code breaks in production with unexpected input
- **Solution:** Think through edge cases, add tests
- **Examples:** null, undefined, empty string, very large numbers

**Pitfall 3: Incomplete PR description**
- **Problem:** Reviewers don't understand context
- **Solution:** Write comprehensive description with why/what/how
- **Template:** Use structured template (summary, changes, testing)

**Pitfall 4: Too large PRs**
- **Problem:** 2000 lines changed, impossible to review
- **Solution:** Break into smaller PRs, use feature flags
- **Guideline:** Keep PRs under 400 lines changed

**Pitfall 5: Merge conflicts**
- **Problem:** PR can't be merged due to conflicts
- **Solution:** Regularly merge main into feature branch
- **Prevention:** Keep branches short-lived

**Pitfall 6: Broken build**
- **Problem:** CI fails after PR submitted
- **Solution:** Run full build locally before creating PR
- **Command:** `npm run build && npm test && npm run lint`

### Tips for Success

1. **Review as if you're the reviewer:** Be critical of your own code
2. **Test thoroughly:** Don't rely on CI to catch issues
3. **Clean commit history:** Make it easy to review commit-by-commit
4. **Small PRs:** Easier to review, faster to merge
5. **Context in description:** Explain why, not just what
6. **Screenshots:** For UI changes, include before/after
7. **Link issues:** Connect PR to issue tracker
8. **Responsive to feedback:** Address comments quickly
9. **Up to date:** Merge main regularly to avoid conflicts
10. **Run CI locally:** Use same tools as CI pipeline

### Self-Review Checklist

**Code Quality:**
- [ ] No debug code (console.log, debugger)
- [ ] No commented-out code
- [ ] Descriptive variable names
- [ ] Functions are focused and small
- [ ] No code duplication
- [ ] Consistent code style
- [ ] Comments for complex logic

**Functionality:**
- [ ] Feature works as expected
- [ ] Edge cases handled
- [ ] Error handling implemented
- [ ] Input validation present
- [ ] No hardcoded values
- [ ] Performance acceptable
- [ ] Security considered

**Tests:**
- [ ] All new code has tests
- [ ] Tests are meaningful
- [ ] Edge cases tested
- [ ] Error cases tested
- [ ] Coverage ≥ 80%
- [ ] Tests follow AAA pattern

**Build & CI:**
- [ ] Build succeeds
- [ ] All tests pass
- [ ] Linting passes
- [ ] Type checking passes (TS)
- [ ] No build warnings

**Documentation:**
- [ ] README updated (if needed)
- [ ] API docs updated
- [ ] Inline comments added
- [ ] Changelog updated

**Git:**
- [ ] Clear commit messages
- [ ] Conventional commits format
- [ ] Logical commit grouping
- [ ] Branch up to date with main
- [ ] No merge conflicts

**PR:**
- [ ] Descriptive title
- [ ] Comprehensive description
- [ ] Screenshots (if UI changes)
- [ ] Linked to issue
- [ ] Reviewers assigned

### Tools & Commands Reference

```bash
# Self-review
git diff main...HEAD                    # View all changes
git diff main...HEAD -- path/to/file    # View specific file changes
git log main..HEAD --oneline            # View commit history
git show <commit-hash>                  # View specific commit

# Testing
npm test                                # Run all tests
npm test -- --coverage                  # Run with coverage
npm test -- --watch                     # Watch mode

# Build
npm run build                           # Build project
rm -rf dist/ && npm run build           # Clean build

# Linting
npm run lint                            # Check linting
npm run lint -- --fix                   # Fix auto-fixable issues

# Formatting
npm run format:check                    # Check formatting
npm run format                          # Format code

# Type checking (TypeScript)
npx tsc --noEmit                        # Type check
npx tsc --noEmit --strict               # Strict type check

# Dependencies
npm audit                               # Security audit
npm outdated                            # Check outdated deps

# Git
git fetch origin                        # Fetch latest
git merge origin/main                   # Merge main
git push origin feature/branch          # Push changes

# GitHub CLI
gh pr create                            # Create PR interactively
gh pr create --title "..." --body "..." # Create with details
```

---

## 5. Debugging Investigation Workflow

### When to Use

- Bug reported by user or QA
- Tests failing unexpectedly
- Production error occurred
- Unexpected behavior observed
- Performance issue detected

### Prerequisites

- Clear description of the issue
- Steps to reproduce (if applicable)
- Error messages or logs
- Environment information

### Step-by-Step Process

#### Step 1: Gather Information

**Collect all available information:**

```bash
# Read error reports
Read: /path/to/error-log.txt

# Check recent commits for related changes
git log --oneline -20

# Search for related issues
gh issue list --search "error message"
```

**Claude Code approach:**
```bash
Read: /logs/error.log
Bash: git log --oneline -20
Bash: gh issue list --search "TypeError"
```

**Information to collect:**
- [ ] Exact error message
- [ ] Steps to reproduce
- [ ] Expected vs actual behavior
- [ ] Environment (OS, browser, versions)
- [ ] When did it start happening?
- [ ] Does it happen consistently?
- [ ] Recent changes that might have caused it

#### Step 2: Reproduce the Issue

**Try to reproduce locally:**

```bash
# Run the application
npm run dev

# Run specific test
npm test -- path/to/failing-test.test.ts

# Run with specific environment
NODE_ENV=production npm start
```

**Claude Code approach:**
```bash
Bash: npm run dev
Bash: npm test -- src/components/Button.test.tsx
```

**Reproduction checklist:**
- [ ] Can reproduce consistently
- [ ] Identified minimal steps to reproduce
- [ ] Isolated to specific component/function
- [ ] Documented reproduction steps

**If can't reproduce:**
- Try different environments
- Check environment variables
- Review configuration differences
- Ask for more information

#### Step 3: Locate the Source

**Use investigation tools to find the problem:**

**Search for error message:**
```bash
# Find where error is thrown
Grep: "Cannot read property" --output_mode content

# Find related code
Grep: "getUserData" --output_mode files_with_matches

# Check function definition
Grep: "function getUserData" --output_mode content -A 20
```

**Claude Code approach:**
```bash
Grep: "Cannot read property" --output_mode content
Grep: "getUserData" --output_mode files_with_matches
Read: /src/api/user.ts
```

**Check git history:**
```bash
# When was this file last changed?
git log --oneline path/to/file.ts

# What changed in recent commits?
git show <commit-hash>

# Who changed this code? (git blame)
git blame path/to/file.ts
```

**Claude Code approach:**
```bash
Bash: git log --oneline src/api/user.ts
Bash: git show abc1234
Bash: git blame src/api/user.ts
```

**Use stack trace:**
```
Error: Cannot read property 'name' of undefined
    at getUserName (src/utils/user.ts:42:20)
    at UserProfile (src/components/UserProfile.tsx:15:10)
    at renderWithHooks (react-dom.js:...)
```

**Follow stack trace:**
```bash
# Read file at line number
Read: /src/utils/user.ts
# Focus on line 42

Read: /src/components/UserProfile.tsx
# Focus on line 15
```

#### Step 4: Form Hypothesis

**Based on investigation, hypothesize the cause:**

**Example hypotheses:**
- "User object is undefined when not logged in"
- "Race condition between API call and render"
- "Data validation missing for edge case"
- "Type mismatch between API response and expected type"

**Validate hypothesis:**
```bash
# Add logging to test hypothesis
Edit: src/utils/user.ts
# Add console.log to verify user object state

# Run code to test
Bash: npm run dev

# Check logs
# Hypothesis confirmed or rejected
```

#### Step 5: Create Failing Test

**Before fixing, create test that reproduces the bug:**

```typescript
// src/utils/user.test.ts
describe('getUserName', () => {
  it('handles undefined user gracefully', () => {
    // This test should fail until bug is fixed
    const result = getUserName(undefined);
    expect(result).toBe('Anonymous');
  });
});
```

**Claude Code approach:**
```bash
Edit: src/utils/user.test.ts
Bash: npm test -- src/utils/user.test.ts
```

**Run test to confirm it fails:**
```bash
npm test -- src/utils/user.test.ts
```

**Benefits:**
- Confirms you understand the bug
- Prevents regression
- Documents expected behavior

#### Step 6: Implement Fix

**Fix the root cause:**

```typescript
// src/utils/user.ts

// BEFORE (buggy)
export function getUserName(user: User): string {
  return user.name; // Crashes if user is undefined
}

// AFTER (fixed)
export function getUserName(user: User | undefined): string {
  if (!user) {
    return 'Anonymous';
  }
  return user.name;
}
```

**Claude Code approach:**
```bash
Edit: src/utils/user.ts
```

**Fix checklist:**
- [ ] Addresses root cause (not just symptoms)
- [ ] Handles edge cases
- [ ] Doesn't break existing functionality
- [ ] Follows existing code patterns
- [ ] Properly typed (if TypeScript)

#### Step 7: Verify Fix

**Run tests:**
```bash
# Run the specific failing test
npm test -- src/utils/user.test.ts

# Run all tests to check for regressions
npm test

# Run related tests
npm test -- src/components/UserProfile.test.tsx
```

**Claude Code approach:**
```bash
Bash: npm test -- src/utils/user.test.ts
Bash: npm test
```

**Manual verification:**
```bash
# Run application
npm run dev

# Follow reproduction steps
# Verify bug no longer occurs
```

**Verification checklist:**
- [ ] Failing test now passes
- [ ] All tests still pass
- [ ] Manual reproduction steps work
- [ ] Edge cases handled
- [ ] No new errors introduced

#### Step 8: Add Comprehensive Tests

**Add tests for edge cases:**

```typescript
describe('getUserName', () => {
  it('returns user name for valid user', () => {
    const user = { id: '1', name: 'John Doe' };
    expect(getUserName(user)).toBe('John Doe');
  });

  it('handles undefined user gracefully', () => {
    expect(getUserName(undefined)).toBe('Anonymous');
  });

  it('handles null user gracefully', () => {
    expect(getUserName(null)).toBe('Anonymous');
  });

  it('handles user with empty name', () => {
    const user = { id: '1', name: '' };
    expect(getUserName(user)).toBe('Anonymous');
  });
});
```

**Claude Code approach:**
```bash
Edit: src/utils/user.test.ts
Bash: npm test -- src/utils/user.test.ts
```

#### Step 9: Document the Fix

**Update relevant documentation:**

```bash
# Add to CHANGELOG
Edit: CHANGELOG.md
```

```markdown
## [1.2.1] - 2026-01-21

### Fixed
- Fixed crash when user is not logged in (#123)
- Added graceful handling for undefined user in getUserName
```

**Add code comments if needed:**
```typescript
export function getUserName(user: User | undefined): string {
  // Handle case when user is not logged in
  // Return 'Anonymous' instead of crashing
  if (!user) {
    return 'Anonymous';
  }
  return user.name;
}
```

**Claude Code approach:**
```bash
Edit: CHANGELOG.md
Edit: src/utils/user.ts
```

#### Step 10: Commit and Deploy

**Commit the fix:**
```bash
git add src/utils/user.ts src/utils/user.test.ts CHANGELOG.md
git commit -m "fix: handle undefined user in getUserName

User was undefined when not logged in, causing crash.
Now returns 'Anonymous' for undefined/null users.

Fixes #123"
```

**Claude Code approach:**
```bash
Bash: git add src/utils/user.ts src/utils/user.test.ts CHANGELOG.md
Bash: git commit -m "fix: handle undefined user in getUserName

User was undefined when not logged in, causing crash.
Now returns 'Anonymous' for undefined/null users.

Fixes #123"
```

**Create PR or deploy:**
```bash
# Push to remote
git push origin fix/123-undefined-user

# Create PR
gh pr create --title "Fix: Handle undefined user" --body "..."

# Or if hotfix, deploy directly
```

### Investigation Techniques

#### Technique 1: Binary Search (git bisect)

**When:** Bug appeared recently but unsure which commit caused it

```bash
# Start bisect
git bisect start

# Mark current commit as bad
git bisect bad

# Mark last known good commit
git bisect good v1.2.0

# Git checks out middle commit
# Test if bug exists
npm test

# Mark as good or bad
git bisect good  # or git bisect bad

# Repeat until found
# Git will identify the culprit commit

# End bisect
git bisect reset
```

#### Technique 2: Stack Trace Analysis

**Read stack traces from bottom to top:**

```
Error: Cannot read property 'name' of undefined
    at getUserName (src/utils/user.ts:42:20)          ← Start here
    at UserProfile (src/components/UserProfile.tsx:15:10)
    at renderWithHooks (react-dom.js:...)
```

**Work backwards:**
1. Where is error thrown? `src/utils/user.ts:42`
2. Who called it? `src/components/UserProfile.tsx:15`
3. What was the state at that point?

#### Technique 3: Rubber Duck Debugging

**Explain the problem out loud (to Claude Code):**

1. Describe what should happen
2. Describe what actually happens
3. Walk through code line by line
4. Often the act of explaining reveals the issue

#### Technique 4: Add Logging

**Strategic console.log placement:**

```typescript
export function processUserData(user: User): ProcessedData {
  console.log('Input user:', user);

  const validated = validateUser(user);
  console.log('After validation:', validated);

  const transformed = transformUser(validated);
  console.log('After transformation:', transformed);

  return transformed;
}
```

**Remember to remove before committing!**

#### Technique 5: Isolate and Simplify

**Create minimal reproduction:**

```typescript
// Isolate problematic code
function testBug() {
  const user = undefined;
  const result = getUserName(user); // Does it crash here?
  console.log(result);
}

testBug();
```

### Example Walkthrough

**Scenario:** Production error: "Cannot read property 'price' of undefined"

```bash
# Step 1: Gather information
Read: /logs/production-error.log

# Error details:
# Error: Cannot read property 'price' of undefined
# at calculateTotal (src/utils/cart.ts:28:30)
# Occurs on checkout page
# Started happening after yesterday's deploy

# Step 2: Check recent commits
Bash: git log --oneline -10
# Found: abc1234 refactor: update cart calculation logic

# Step 3: Reproduce locally
Bash: npm run dev
# Navigate to checkout page
# Add items to cart
# Click checkout
# Error reproduced ✓

# Step 4: Locate source
Read: /src/utils/cart.ts

# Line 28:
# const total = items.reduce((sum, item) => sum + item.price * item.quantity, 0);
# Problem: Some items don't have price property

# Check why
Grep: "item.price" --output_mode content
# Found items can be null when out of stock

# Step 5: Form hypothesis
# Hypothesis: Items that are out of stock return null from API
# This causes item.price to be undefined

# Step 6: Create failing test
Edit: src/utils/cart.test.ts
```

```typescript
it('handles items without price gracefully', () => {
  const items = [
    { id: '1', price: 10, quantity: 2 },
    { id: '2', price: undefined, quantity: 1 }, // Out of stock
  ];
  expect(() => calculateTotal(items)).not.toThrow();
});
```

```bash
Bash: npm test -- src/utils/cart.test.ts
# Test fails as expected ✓

# Step 7: Implement fix
Edit: src/utils/cart.ts
```

```typescript
export function calculateTotal(items: CartItem[]): number {
  return items.reduce((sum, item) => {
    // Skip items without price (out of stock)
    if (!item || typeof item.price !== 'number') {
      return sum;
    }
    return sum + item.price * item.quantity;
  }, 0);
}
```

```bash
# Step 8: Verify fix
Bash: npm test -- src/utils/cart.test.ts
# Test passes ✓

Bash: npm test
# All tests pass ✓

Bash: npm run dev
# Manual test: checkout with out-of-stock item
# Works correctly ✓

# Step 9: Add comprehensive tests
Edit: src/utils/cart.test.ts
```

```typescript
describe('calculateTotal', () => {
  it('calculates total for valid items', () => {
    const items = [
      { id: '1', price: 10, quantity: 2 },
      { id: '2', price: 5, quantity: 3 },
    ];
    expect(calculateTotal(items)).toBe(35);
  });

  it('handles items without price gracefully', () => {
    const items = [
      { id: '1', price: 10, quantity: 2 },
      { id: '2', price: undefined, quantity: 1 },
    ];
    expect(calculateTotal(items)).toBe(20);
  });

  it('handles empty cart', () => {
    expect(calculateTotal([])).toBe(0);
  });

  it('handles all items out of stock', () => {
    const items = [
      { id: '1', price: undefined, quantity: 1 },
      { id: '2', price: undefined, quantity: 1 },
    ];
    expect(calculateTotal(items)).toBe(0);
  });
});
```

```bash
# Step 10: Commit and deploy
Bash: git add src/utils/cart.ts src/utils/cart.test.ts
Bash: git commit -m "fix: handle items without price in cart calculation

Out-of-stock items can have undefined price, causing crash.
Now gracefully skips items without valid price.

Fixes #456"

Bash: git push origin fix/456-cart-calculation
Bash: gh pr create --title "Fix: Handle out-of-stock items in cart" --body "..."
```

### Common Pitfalls

**Pitfall 1: Fixing symptoms, not root cause**
- **Problem:** Add null check without understanding why value is null
- **Solution:** Investigate why value is null in the first place
- **Example:** Don't just add `if (user)`, understand why user is undefined

**Pitfall 2: Not reproducing before fixing**
- **Problem:** Can't verify fix works
- **Solution:** Always reproduce issue before attempting fix
- **Benefit:** Confirms understanding of problem

**Pitfall 3: No test for regression**
- **Problem:** Bug comes back in future
- **Solution:** Add test that would fail if bug returns
- **Best practice:** Test-driven debugging

**Pitfall 4: Incomplete investigation**
- **Problem:** Fix one case but miss others
- **Solution:** Think through all edge cases
- **Example:** Handle null, undefined, empty string, etc.

**Pitfall 5: Breaking existing functionality**
- **Problem:** Fix one bug, introduce another
- **Solution:** Run full test suite before and after
- **Safety:** Run tests frequently during debugging

### Tips for Success

1. **Reproduce first:** Can't fix what you can't reproduce
2. **Understand before fixing:** Don't rush to code
3. **Add tests:** Prevent regression
4. **Think edge cases:** null, undefined, empty, very large
5. **Use version control:** git bisect for recent bugs
6. **Read stack traces:** They tell you exactly where error occurred
7. **Search codebase:** Find similar code for patterns
8. **Ask for help:** If stuck, explain problem to someone
9. **Document findings:** Help future debuggers
10. **Fix root cause:** Not just symptoms

### Tools & Commands Reference

```bash
# Investigation
git log --oneline -20                   # Recent commits
git log path/to/file.ts                 # File history
git blame path/to/file.ts               # Line-by-line authorship
git show <commit-hash>                  # View specific commit
git diff <commit1> <commit2>            # Compare commits

# Search
Grep: "error message" --output_mode content
Grep: "function name" --output_mode files_with_matches
Glob: "**/*keyword*"

# Testing
npm test                                # Run all tests
npm test -- path/to/file.test.ts        # Run specific test
npm test -- --watch                     # Watch mode
npm test -- --coverage                  # Coverage report

# Debugging
npm run dev                             # Run in development
NODE_ENV=production npm start           # Run in production mode

# Git bisect (find bug-introducing commit)
git bisect start                        # Start bisect
git bisect bad                          # Mark current as bad
git bisect good v1.0.0                  # Mark known good version
# Test and mark good/bad until found
git bisect reset                        # End bisect

# Dependencies
npm list <package>                      # Check if package installed
npm outdated                            # Check outdated packages
npm audit                               # Security vulnerabilities
```

---

## 6. Safe Refactoring Pattern

### When to Use

- Code is difficult to understand or maintain
- Code duplication exists
- Performance needs improvement
- Preparing to add new feature
- Improving code quality

### Prerequisites

- Comprehensive test coverage (≥80%)
- Understanding of code being refactored
- Clear goal for refactoring
- Time to do it properly

### Step-by-Step Process

#### Step 1: Ensure Test Coverage

**Before refactoring anything, ensure tests exist:**

```bash
# Check current coverage
npm test -- --coverage

# Review coverage report
Read: coverage/coverage-summary.json
Read: coverage/lcov-report/index.html
```

**Claude Code approach:**
```bash
Bash: npm test -- --coverage
Read: coverage/coverage-summary.json
```

**Coverage assessment:**
- [ ] Overall coverage ≥ 80%
- [ ] Code to refactor has ≥ 80% coverage
- [ ] All critical paths tested
- [ ] Edge cases covered

**If coverage insufficient, add tests first:**

```typescript
// Add tests BEFORE refactoring
describe('legacyFunction', () => {
  it('handles normal case', () => { });
  it('handles edge case A', () => { });
  it('handles edge case B', () => { });
  it('handles error case', () => { });
});
```

**Run tests to establish baseline:**
```bash
npm test
```

All tests must pass before starting refactoring.

#### Step 2: Create Refactoring Branch

```bash
# Create dedicated refactoring branch
git checkout -b refactor/123-extract-validation-logic

# Verify clean state
git status
```

**Claude Code approach:**
```bash
Bash: git checkout -b refactor/123-extract-validation-logic
Bash: git status
```

**Why dedicated branch:**
- Isolates refactoring work
- Easy to revert if needed
- Clear scope in git history

#### Step 3: Make Small, Incremental Changes

**Refactor in tiny steps:**

**Anti-pattern: Big bang refactoring**
```bash
# ❌ BAD - Change everything at once
# - Rename 20 functions
# - Extract 10 components
# - Restructure entire directory
# - All in one commit
```

**Best practice: Incremental refactoring**
```bash
# ✅ GOOD - One change at a time
# 1. Extract one function
# 2. Run tests
# 3. Commit
# 4. Extract next function
# 5. Run tests
# 6. Commit
```

**Example refactoring steps:**

**Step 1: Extract function**
```typescript
// BEFORE
function processUserData(user: User): ProcessedUser {
  // Validation logic inline
  if (!user.email || !user.email.includes('@')) {
    throw new Error('Invalid email');
  }
  if (!user.name || user.name.length < 2) {
    throw new Error('Invalid name');
  }

  // Processing logic
  return {
    ...user,
    email: user.email.toLowerCase(),
    name: user.name.trim(),
  };
}

// AFTER - Extract validation
function validateUser(user: User): void {
  if (!user.email || !user.email.includes('@')) {
    throw new Error('Invalid email');
  }
  if (!user.name || user.name.length < 2) {
    throw new Error('Invalid name');
  }
}

function processUserData(user: User): ProcessedUser {
  validateUser(user);

  return {
    ...user,
    email: user.email.toLowerCase(),
    name: user.name.trim(),
  };
}
```

**Claude Code approach:**
```bash
Edit: src/utils/user.ts
```

**Run tests after each change:**
```bash
npm test -- src/utils/user.test.ts
```

**Commit immediately:**
```bash
git add src/utils/user.ts
git commit -m "refactor: extract user validation logic"
```

**Step 2: Extract another function**
```typescript
// Extract formatting logic
function formatUser(user: User): User {
  return {
    ...user,
    email: user.email.toLowerCase(),
    name: user.name.trim(),
  };
}

function processUserData(user: User): ProcessedUser {
  validateUser(user);
  return formatUser(user);
}
```

**Run tests:**
```bash
npm test -- src/utils/user.test.ts
```

**Commit:**
```bash
git add src/utils/user.ts
git commit -m "refactor: extract user formatting logic"
```

#### Step 4: Run Tests Continuously

**After EVERY change, run tests:**

```bash
# Run specific test file
npm test -- src/utils/user.test.ts

# Or use watch mode
npm test -- --watch
```

**Claude Code approach:**
```bash
Bash: npm test -- src/utils/user.test.ts
```

**Test frequency:**
- ✅ After every function extraction
- ✅ After every rename
- ✅ After every file move
- ✅ After every logic change

**If tests fail:**
1. Stop immediately
2. Review what changed
3. Fix the issue
4. Don't continue until tests pass

#### Step 5: Commit Frequently

**Commit after each successful refactoring step:**

```bash
# Commit each small change
git add src/utils/user.ts
git commit -m "refactor: extract validation logic"

# Next change
git add src/utils/user.ts
git commit -m "refactor: extract formatting logic"

# Next change
git add src/utils/user.ts src/utils/validation.ts
git commit -m "refactor: move validation to separate file"
```

**Claude Code approach:**
```bash
Bash: git add src/utils/user.ts
Bash: git commit -m "refactor: extract validation logic"
```

**Benefits of frequent commits:**
- Easy to revert single change if needed
- Clear history of refactoring steps
- Checkpoint progress
- Can pause and resume easily

#### Step 6: Update Tests (If Needed)

**If refactoring changes public API, update tests:**

```typescript
// BEFORE refactoring
describe('processUserData', () => {
  it('throws on invalid email', () => {
    expect(() => processUserData({ email: 'bad', name: 'John' }))
      .toThrow('Invalid email');
  });
});

// AFTER extracting validateUser
// Add dedicated tests for new function
describe('validateUser', () => {
  it('throws on invalid email', () => {
    expect(() => validateUser({ email: 'bad', name: 'John' }))
      .toThrow('Invalid email');
  });

  it('throws on invalid name', () => {
    expect(() => validateUser({ email: 'john@example.com', name: 'J' }))
      .toThrow('Invalid name');
  });
});

// Keep integration test for processUserData
describe('processUserData', () => {
  it('processes valid user', () => {
    const user = { email: 'JOHN@EXAMPLE.COM', name: '  John  ' };
    const result = processUserData(user);
    expect(result.email).toBe('john@example.com');
    expect(result.name).toBe('John');
  });
});
```

**Claude Code approach:**
```bash
Edit: src/utils/user.test.ts
Bash: npm test -- src/utils/user.test.ts
```

#### Step 7: Update Documentation

**Update docs to reflect refactoring:**

```bash
# Update README if API changed
Edit: README.md

# Update inline comments
Edit: src/utils/user.ts

# Update API documentation
Edit: docs/api.md
```

**Claude Code approach:**
```bash
Edit: README.md
Edit: src/utils/user.ts
```

**Documentation to update:**
- [ ] README (if public API changed)
- [ ] API documentation
- [ ] Inline code comments
- [ ] Architecture diagrams
- [ ] Usage examples

#### Step 8: Performance Check

**Verify refactoring didn't hurt performance:**

```bash
# Run performance benchmarks (if available)
npm run benchmark

# Check bundle size
npm run build
# Compare bundle size before/after
```

**Claude Code approach:**
```bash
Bash: npm run build
```

**Performance checklist:**
- [ ] Build time similar or better
- [ ] Bundle size similar or smaller
- [ ] Runtime performance not degraded
- [ ] No new memory leaks

**If performance regression:**
- Profile the code
- Identify bottleneck
- Optimize or revert

#### Step 9: Final Verification

**Run full verification suite:**

```bash
# Run all tests
npm test

# Check coverage (should be same or better)
npm test -- --coverage

# Build
npm run build

# Lint
npm run lint

# Type check (TypeScript)
npx tsc --noEmit
```

**Claude Code approach:**
```bash
Bash: npm test -- --coverage
Bash: npm run build && npm run lint
Bash: npx tsc --noEmit
```

**Final checklist:**
- [ ] All tests pass
- [ ] Coverage maintained or improved
- [ ] Build succeeds
- [ ] Linting passes
- [ ] Type checking passes
- [ ] No functional changes
- [ ] Documentation updated
- [ ] Performance acceptable

#### Step 10: Create Refactoring PR

**Create PR with clear description:**

```markdown
## Summary
Refactored user data processing to improve maintainability.

## Changes
- Extracted validation logic to separate function
- Extracted formatting logic to separate function
- Moved validation to dedicated module
- Added comprehensive tests for extracted functions

## Non-Functional Changes
This is a pure refactoring - no behavior changes.

## Testing
- All existing tests pass
- Added tests for extracted functions
- Coverage maintained at 85%
- Performance benchmarks unchanged

## Before/After
[Code comparison showing improvement in readability]
```

**Claude Code approach:**
```bash
Bash: git push origin refactor/123-extract-validation-logic
Bash: gh pr create --title "Refactor: Extract user validation logic" --body "..."
```

### Refactoring Patterns

#### Pattern 1: Extract Function

**When:** Function doing too many things

**Before:**
```typescript
function processOrder(order: Order): ProcessedOrder {
  // Validation
  if (!order.items || order.items.length === 0) {
    throw new Error('Order must have items');
  }

  // Calculate total
  const total = order.items.reduce((sum, item) => sum + item.price * item.quantity, 0);

  // Apply discount
  const discount = total > 100 ? total * 0.1 : 0;
  const finalTotal = total - discount;

  // Format result
  return {
    ...order,
    total: finalTotal,
    discount,
  };
}
```

**After:**
```typescript
function validateOrder(order: Order): void {
  if (!order.items || order.items.length === 0) {
    throw new Error('Order must have items');
  }
}

function calculateTotal(items: OrderItem[]): number {
  return items.reduce((sum, item) => sum + item.price * item.quantity, 0);
}

function calculateDiscount(total: number): number {
  return total > 100 ? total * 0.1 : 0;
}

function processOrder(order: Order): ProcessedOrder {
  validateOrder(order);

  const total = calculateTotal(order.items);
  const discount = calculateDiscount(total);
  const finalTotal = total - discount;

  return {
    ...order,
    total: finalTotal,
    discount,
  };
}
```

#### Pattern 2: Extract Constant

**When:** Magic numbers or repeated values

**Before:**
```typescript
function calculateShipping(weight: number): number {
  if (weight < 5) {
    return 4.99;
  } else if (weight < 10) {
    return 7.99;
  } else {
    return 12.99;
  }
}
```

**After:**
```typescript
const SHIPPING_RATES = {
  LIGHT: { maxWeight: 5, cost: 4.99 },
  MEDIUM: { maxWeight: 10, cost: 7.99 },
  HEAVY: { cost: 12.99 },
};

function calculateShipping(weight: number): number {
  if (weight < SHIPPING_RATES.LIGHT.maxWeight) {
    return SHIPPING_RATES.LIGHT.cost;
  } else if (weight < SHIPPING_RATES.MEDIUM.maxWeight) {
    return SHIPPING_RATES.MEDIUM.cost;
  } else {
    return SHIPPING_RATES.HEAVY.cost;
  }
}
```

#### Pattern 3: Rename for Clarity

**When:** Variable/function names are unclear

**Before:**
```typescript
function calc(u: User, o: Order): number {
  const t = o.items.reduce((s, i) => s + i.p * i.q, 0);
  const d = u.lvl === 'premium' ? 0.2 : 0;
  return t * (1 - d);
}
```

**After:**
```typescript
function calculateOrderTotal(user: User, order: Order): number {
  const subtotal = order.items.reduce(
    (sum, item) => sum + item.price * item.quantity,
    0
  );
  const discountRate = user.level === 'premium' ? 0.2 : 0;
  return subtotal * (1 - discountRate);
}
```

#### Pattern 4: Reduce Nesting

**When:** Too many nested conditionals

**Before:**
```typescript
function processUser(user: User): ProcessedUser {
  if (user) {
    if (user.email) {
      if (user.email.includes('@')) {
        if (user.name) {
          return { ...user, valid: true };
        } else {
          throw new Error('Name required');
        }
      } else {
        throw new Error('Invalid email');
      }
    } else {
      throw new Error('Email required');
    }
  } else {
    throw new Error('User required');
  }
}
```

**After:**
```typescript
function processUser(user: User): ProcessedUser {
  if (!user) {
    throw new Error('User required');
  }
  if (!user.email) {
    throw new Error('Email required');
  }
  if (!user.email.includes('@')) {
    throw new Error('Invalid email');
  }
  if (!user.name) {
    throw new Error('Name required');
  }

  return { ...user, valid: true };
}
```

### Example Walkthrough

**Scenario:** Refactor complex shopping cart calculation

```bash
# Step 1: Check test coverage
Bash: npm test -- src/utils/cart.ts --coverage
# Coverage: 65% - need more tests first

# Add missing tests before refactoring
Edit: src/utils/cart.test.ts
```

```typescript
describe('calculateCartTotal', () => {
  it('calculates total with tax', () => { });
  it('applies discount for premium users', () => { });
  it('handles empty cart', () => { });
  it('handles out-of-stock items', () => { });
});
```

```bash
Bash: npm test -- src/utils/cart.test.ts
# Coverage now 85% ✓

# Step 2: Create refactoring branch
Bash: git checkout -b refactor/456-simplify-cart-calculation

# Step 3: Read current implementation
Read: /src/utils/cart.ts

# Current code is 150 lines, complex nested logic
# Plan: Extract functions for each responsibility

# Step 4: Extract tax calculation
Edit: src/utils/cart.ts
```

```typescript
// Extract tax calculation
function calculateTax(subtotal: number, taxRate: number): number {
  return subtotal * taxRate;
}
```

```bash
# Run tests
Bash: npm test -- src/utils/cart.test.ts
# All pass ✓

# Commit
Bash: git add src/utils/cart.ts
Bash: git commit -m "refactor: extract tax calculation"

# Step 5: Extract discount calculation
Edit: src/utils/cart.ts
```

```typescript
function calculateDiscount(subtotal: number, user: User): number {
  if (user.level === 'premium') {
    return subtotal * 0.2;
  }
  if (subtotal > 100) {
    return subtotal * 0.1;
  }
  return 0;
}
```

```bash
# Run tests
Bash: npm test -- src/utils/cart.test.ts
# All pass ✓

# Commit
Bash: git add src/utils/cart.ts
Bash: git commit -m "refactor: extract discount calculation"

# Step 6: Extract item total calculation
Edit: src/utils/cart.ts
```

```typescript
function calculateItemTotal(item: CartItem): number {
  if (!item || !item.price) {
    return 0;
  }
  return item.price * item.quantity;
}
```

```bash
# Run tests
Bash: npm test -- src/utils/cart.test.ts
# All pass ✓

# Commit
Bash: git add src/utils/cart.ts
Bash: git commit -m "refactor: extract item total calculation"

# Step 7: Simplify main function
Edit: src/utils/cart.ts
```

```typescript
function calculateCartTotal(cart: Cart, user: User, taxRate: number): number {
  const subtotal = cart.items.reduce(
    (sum, item) => sum + calculateItemTotal(item),
    0
  );

  const discount = calculateDiscount(subtotal, user);
  const subtotalAfterDiscount = subtotal - discount;

  const tax = calculateTax(subtotalAfterDiscount, taxRate);
  const total = subtotalAfterDiscount + tax;

  return total;
}
```

```bash
# Run tests
Bash: npm test -- src/utils/cart.test.ts
# All pass ✓

# Commit
Bash: git add src/utils/cart.ts
Bash: git commit -m "refactor: simplify cart total calculation"

# Step 8: Add tests for extracted functions
Edit: src/utils/cart.test.ts
```

```typescript
describe('calculateTax', () => {
  it('calculates tax correctly', () => {
    expect(calculateTax(100, 0.1)).toBe(10);
  });
});

describe('calculateDiscount', () => {
  it('applies premium discount', () => { });
  it('applies bulk discount', () => { });
  it('returns 0 for no discount', () => { });
});

describe('calculateItemTotal', () => {
  it('handles valid item', () => { });
  it('handles item without price', () => { });
});
```

```bash
# Run tests
Bash: npm test -- src/utils/cart.test.ts --coverage
# Coverage: 92% ✓

# Commit
Bash: git add src/utils/cart.test.ts
Bash: git commit -m "test: add coverage for extracted functions"

# Step 9: Final verification
Bash: npm test
# All tests pass ✓

Bash: npm run build && npm run lint
# Build succeeds, no lint errors ✓

# Step 10: Create PR
Bash: git push origin refactor/456-simplify-cart-calculation
Bash: gh pr create --title "Refactor: Simplify cart calculation" --body "..."
```

### Common Pitfalls

**Pitfall 1: Refactoring without tests**
- **Problem:** No way to verify changes don't break functionality
- **Solution:** Add tests first, then refactor
- **Rule:** Never refactor code with <80% coverage

**Pitfall 2: Big bang refactoring**
- **Problem:** Change everything at once, impossible to debug
- **Solution:** Small incremental changes, test after each
- **Example:** Extract one function at a time

**Pitfall 3: Changing behavior during refactoring**
- **Problem:** Refactoring should be behavior-neutral
- **Solution:** Keep behavior identical, only improve structure
- **Test:** All existing tests should still pass

**Pitfall 4: Not committing frequently**
- **Problem:** Can't easily revert if something goes wrong
- **Solution:** Commit after each successful refactoring step
- **Benefit:** Clear history, easy to revert

**Pitfall 5: Skipping performance check**
- **Problem:** Refactoring accidentally degrades performance
- **Solution:** Benchmark before and after
- **Tools:** Performance profiling, bundle size analysis

### Tips for Success

1. **Tests first:** Ensure ≥80% coverage before refactoring
2. **Small steps:** One change at a time
3. **Run tests constantly:** After every change
4. **Commit frequently:** Each successful step
5. **Behavior-neutral:** Don't change functionality
6. **Clear goal:** Know what you're improving
7. **Use tools:** Automated refactoring tools (IDE support)
8. **Don't rush:** Take time to do it properly
9. **Document:** Update docs and comments
10. **Pair refactoring:** Two sets of eyes catch more issues

### Refactoring Checklist

**Before starting:**
- [ ] Test coverage ≥ 80%
- [ ] All tests passing
- [ ] Clear refactoring goal
- [ ] Time to do it properly
- [ ] Created dedicated branch

**During refactoring:**
- [ ] Small incremental changes
- [ ] Run tests after each change
- [ ] Commit after each successful change
- [ ] No behavior changes
- [ ] Keep it reversible

**After refactoring:**
- [ ] All tests still pass
- [ ] Coverage maintained or improved
- [ ] Build succeeds
- [ ] Linting passes
- [ ] Type checking passes
- [ ] Performance acceptable
- [ ] Documentation updated
- [ ] Clear PR description

### Tools & Commands Reference

```bash
# Testing
npm test                                # Run all tests
npm test -- path/to/file.test.ts        # Run specific test
npm test -- --watch                     # Watch mode
npm test -- --coverage                  # Coverage report

# Build & Verification
npm run build                           # Build project
npm run lint                            # Lint code
npx tsc --noEmit                        # Type check (TS)

# Git
git checkout -b refactor/description    # Create refactoring branch
git add file.ts                         # Stage changes
git commit -m "refactor: description"   # Commit refactoring
git push origin refactor/description    # Push branch

# Performance
npm run benchmark                       # Run benchmarks (if available)
npm run build -- --analyze              # Analyze bundle size

# IDE Refactoring (VSCode)
F2                                      # Rename symbol
Ctrl+Shift+R                            # Refactor menu
Ctrl+.                                  # Quick fix
```

---

## WSL-Specific Considerations

### Git Operations in WSL

**Path handling:**
```bash
# WSL uses Linux-style paths
/home/fred/projects/myproject

# Windows paths accessible via /mnt/
/mnt/c/Users/Fred/Projects/myproject

# Best practice: Keep projects in WSL filesystem for performance
```

**Git configuration:**
```bash
# Configure Git for WSL
git config --global core.autocrlf input
git config --global core.eol lf

# Check current config
git config --list
```

**SSH keys:**
```bash
# SSH keys should be in WSL, not Windows
# Generate SSH key in WSL
ssh-keygen -t ed25519 -C "your_email@example.com"

# Add to SSH agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Add public key to GitHub
cat ~/.ssh/id_ed25519.pub
```

**Performance:**
```bash
# Much faster: Project in WSL filesystem
/home/fred/projects/myproject
git status  # Fast

# Slower: Project in Windows filesystem
/mnt/c/Users/Fred/Projects/myproject
git status  # Slower due to cross-filesystem access
```

### File System Differences

**Line endings:**
```bash
# WSL uses LF (Linux)
# Windows uses CRLF

# Configure Git to handle this
git config --global core.autocrlf input

# Or use .gitattributes
echo "* text=auto eol=lf" > .gitattributes
```

**Case sensitivity:**
```bash
# WSL is case-sensitive
# Windows is case-insensitive

# Potential issues:
# - File.ts vs file.ts are different in WSL
# - Same file in Windows

# Best practice: Use consistent casing
```

**Permissions:**
```bash
# Check file permissions in WSL
ls -la

# Make script executable
chmod +x script.sh

# Windows filesystem permissions may not translate
```

### Environment Variables

**Setting environment variables:**
```bash
# In WSL: ~/.bashrc or ~/.zshrc
export NODE_ENV=development
export API_KEY=abc123

# Reload shell config
source ~/.bashrc

# Or use .env file (project-specific)
```

**Path environment:**
```bash
# WSL PATH is separate from Windows PATH
echo $PATH

# Add to PATH in ~/.bashrc
export PATH="$HOME/.local/bin:$PATH"
```

### Docker Integration

**Docker Desktop with WSL2:**
```bash
# Docker Desktop integrates with WSL2
# Docker commands work natively in WSL

docker ps
docker-compose up
```

**MCP servers using Docker:**
```bash
# GitHub MCP server works in WSL
# Docker containers accessible from WSL
```

### Common WSL Commands

```bash
# Check WSL version
wsl --version

# List WSL distributions
wsl --list --verbose

# Set default distribution
wsl --set-default Ubuntu

# Update WSL
wsl --update

# Shutdown WSL
wsl --shutdown

# Convert path Windows → WSL
wslpath 'C:\Users\Fred\project'
# Output: /mnt/c/Users/Fred/project

# Convert path WSL → Windows
wslpath -w /home/fred/project
# Output: \\wsl$\Ubuntu\home\fred\project
```

### Best Practices for WSL

1. **Keep projects in WSL filesystem:** `/home/...` for performance
2. **Use WSL-native tools:** Install node, npm, git in WSL
3. **Configure Git properly:** Handle line endings correctly
4. **Use SSH keys in WSL:** Not Windows SSH keys
5. **Be aware of case sensitivity:** Consistent file naming
6. **Use WSL terminal:** Windows Terminal or VSCode terminal
7. **Docker Desktop integration:** Enable WSL2 backend
8. **Environment variables in WSL:** Configure in `~/.bashrc`

---

## Summary

This workflows document provides practical, step-by-step patterns for common development tasks:

1. **Atomic Commit Workflow:** Small, focused commits with clear messages
2. **Feature Development Workflow:** From branch creation to merged PR
3. **Test-Driven Development Pattern:** Red → Green → Refactor cycle
4. **Code Review Preparation:** Self-review checklist before submitting
5. **Debugging Investigation Workflow:** Systematic problem-solving
6. **Safe Refactoring Pattern:** Improve code without breaking functionality

**Key Principles:**
- Small incremental changes
- Test continuously
- Commit frequently
- Clear communication
- Safety first

**For WSL users:**
- Keep projects in native WSL filesystem
- Configure Git for line endings
- Use WSL-native tools
- SSH keys in WSL environment

**Remember:** These workflows are guidelines, not rigid rules. Adapt to your team's practices and project requirements.

---

**Last Updated:** 2026-01-21
**See Also:**
- [CLAUDE.md](/home/fred/projects/dotfiles/CLAUDE.md) - Comprehensive development guidelines
- [MCP Servers Guide](/home/fred/projects/dotfiles/docs/mcp-servers.md) - MCP server setup and usage

**Contributing:** Found a better workflow? Update this document and share with the team!
