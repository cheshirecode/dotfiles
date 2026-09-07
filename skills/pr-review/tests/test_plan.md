# pr-review skill — test plan

Three fixtures in this directory carry the automated cases, and `tests/run.sh
fixtures` globs `skills/*/tests/test_*.sh`, so each runs in the suite:

- `test_pr_review_bin.sh` — script-level cases 1a, 1b, 1g–1j, 2a, 2c, 2e, plus
  token forwarding, missing option values, the execute bits, the
  cross-skill-path ban, and shellcheck.
- `test_forge_no_origin.sh` — case 1c, a repo with no `origin`.
- `test_forge_hosts.sh` — cases 4a–4c, which host counts as which forge.

Three ways `owner-check.sh` can fail to establish an owner are pinned
alongside 1d, because each is caught by a different guard and each would
otherwise produce a verdict on a PR that was never read: a 404, a payload that
is empty, and a payload that is well formed with a null author. An
unresolvable current user is pinned too — that guard is what makes the
`-n "$AUTHOR"` term in the comparison unreachable.

The rest of this file is the manual plan for cases that need a live PR.

Case 1j is automated against a throwaway clone with a GitLab origin, not by
editing this repo's own remote and restoring it. A checkout is shared: a
"temporarily set, then restore" step can be observed, or interrupted, halfway.

## Test categories

### 1. Script-level tests (bin/detect-forge.sh, bin/owner-check.sh)

| # | Test | Expected | How to verify |
|---|------|----------|---------------|
| 1a | detect: non-git directory | Exit 2, "not a git repository" message | `detect-forge.sh --repo /tmp/not-a-repo-test`; assert exit code |
| 1b | detect: dotfiles repo (GitHub) | Exit 0, stdout contains `github`, CLI = `gh` | Run on `/Users/fredtran/Documents/oss/dotfiles` |
| 1c | detect: missing origin remote | Exit 2, clear error | Create bare clone with no origin configured |
| 1d | owner-check.sh: non-existent PR | Exit 2, error naming the PR number on stderr, empty stdout | Automated fake `gh` 404s any number but the known one |
| 1e | owner-check.sh: current user's own PR | Exit 0, stdout = "self" | Automated fake `gh` returns a PR whose author is the current user |
| 1f | owner-check.sh: another user's PR | Exit 1, stdout = "other" | Find any PR not opened by cheshirecode |
| 1g | owner-check.sh: no args | Exit 2, usage message | `owner-check.sh` with zero args |
| 1h | owner-check.sh: with --token override | Exports the override to the selected forge CLI | Automated fake `gh` rejects the API call unless `GH_TOKEN` matches |
| 1i | PR author differs but a commit author matches | Exit 1, stdout = "other" | Automated fake `gh` returns different PR/current users and a matching commit author |
| 1j | Forge: GitLab URL (simulated) | classify_remote returns `gitlab\towner/group-slug` | Automated: throwaway repo with a GitLab origin, `detect-forge.sh --repo` against it. Never edit this checkout's origin |

**Note for 1c:** automated in `test_forge_no_origin.sh`, against throwaway
repos: one with no remote at all, one with an `upstream` but no `origin`.
1b and 1j build throwaway repos too, so none of the three reads the real remote.

### 2. Script-level tests (bin/pr-query.sh)

| # | Test | Expected | How to verify |
|---|------|----------|---------------|
| 2a | pr-query.sh view (GitHub PR) | Valid JSON with number, title, author fields | `pr-query.sh view <n>` on an open dotfiles PR; jq-parse output |
| 2b | pr-query.sh diff (GitHub PR) | Unified diff text, non-empty for changed files | `pr-query.sh diff <n>`; check exit code, pipe to wc -l |
| 2c | pr-query.sh merge-base | Returns the merge base against the remote default branch | Automated repo keeps local `main` stale while the feature starts from `origin/main` |
| 2d | pr-query.sh: missing auth | Exit 2, clear error message about unauthenticated CLI | Temporarily unset GH_TOKEN, run any query |
| 2e | pr-query.sh: invalid PR number | Exit 1 or 2, error on stderr (not silent failure) | `pr-query.sh view 999999`; assert non-zero exit |
| 2f | pr-query.sh: --repo override | Uses specified repo's remote, not cwd | Set up a mock GitLab-origin checkout, run with --repo pointing to it |

### 3. Shell mechanic tests (adversarial review infrastructure)

| # | Test | Expected | How to verify |
|---|------|----------|---------------|
| 3a | Wrong checkout trap | Grep succeeds in wrong branch, fails in right one | Check out a branch where the target doesn't exist, grep for it → exits non-zero even though it exists on another branch |
| 3b | Silenced error trap | `cmd 2>/dev/null | wc -l` returns 0 even when cmd fails | `cat /root/nonexistent 2>/dev/null | wc -l` → prints 0 (exit 1 from cat swallowed by pipe) |
| 3c | Masked exit code trap | `echo $?` after pipe reports last command's status | `true | false; echo $?` → prints 1 (false's exit, not true's) |
| 3d | Stale merge-base | Diff against stale merge-base includes already-merged changes | Merge something into main locally, then diff a topic branch against the OLD recorded merge-base vs re-computed one |
| 3e | Leak-scan exit codes | Clean input → 0, leaks → 1, empty → 2 | Pipe known strings through leak-scan.sh --label body |
| 3f | Stash+test cycle | `git stash push -u && git stash pop` preserves untracked files | Create a new file, `git stash push -u`, verify file disappears, `git stash pop`, verify file returns |

### 4. Forge-agnostic integration tests

| # | Test | Expected | How to verify |
|---|------|----------|---------------|
| 4a | detect-forge: GitHub SSH remote (git@github.com:o/r.git) | forge=github, CLI=gh | Automated in `test_forge_hosts.sh`, both URL forms, against throwaway repos |
| 4b | detect-forge: GitLab HTTPS remote (https://gitlab.com/o/r.git) | forge=gitlab, CLI=glab | Automated in `test_forge_hosts.sh`; also pins the vendors' alternate SSH hosts (ssh.github.com, altssh.gitlab.com) |
| 4c | detect-forge: Self-hosted GitHub (github.mycompany.com) | forge=other, CLI empty, reason `unsupported-forge-host` | Automated in `test_forge_hosts.sh`. Was a live defect: the old `github.*` glob matched this host and returned CLI=gh |
| 4d | owner-check.sh with --token bypasses auth | The selected CLI receives the override token | Automated fake `gh` requires the exact token on both API calls |
| 4e | owner-check.sh: GitLab MR (simulated auth) | Uses glab API path, not gh | Requires GitLab setup; validate code path via tracing |

### 5. SKILL.md integration tests (loop-engineering routing)

| # | Test | Expected | How to verify |
|---|------|----------|---------------|
| 5a | Loop-engineering can find $pr-review | `$pr-review` resolves correctly in routing table | Search loop-engineering/SKILL.md for pr-review entry |
| 5b | Tightening-a-pr shim delegates to pr-review | Loading tightening-a-pr triggers pr-review | Load both skills; verify tightening-a-pr SKILL.md says "delegates to $pr-review" |
| 5c | Ship-hygiene still references leak-scan.sh | No broken delegation in ship-hygiene step 7 | Read ship-hygiene/SKILL.md step 7b, confirm `<skill-dir>` resolution still works |
| 5d | SKILL_DIR resolver finds pr-review across all roots | `find -L ~/.claude/skills ...` and `~/.agents/skills ...` both locate pr-review | Run the resolver pattern against pr-review name |

### 6. Edge-case scenarios (review modes)

| # | Scenario | Mode selected | Expected behavior |
|---|----------|---------------|-------------------|
| 6a | Review draft PR (own) | self-check | Warn that review is premature; skip deep code audit |
| 6b | Review draft PR (others') | other-review | Structural audit only; skip adversarial assumption attacks |
| 6c | Review merged PR (retrospective) | other-review | Full adversarial pass possible; no live-edit risk |
| 6d | Review closed/deleted PR | other-review (conservative) | pr-query.sh view may fail; handle gracefully, flag incomplete data |
| 6e | Owner detection ambiguous (null author, email-only) | other-review (default) | Cannot confirm PR authorship, so defaults to "other" |
| 6f | Self-check depth budget exceeded (diff > 500 lines) | self-check | Log warning, either proceed with reduced scope or request confirmation |
| 6g | Other-review with green CI + clean leak-scan + coherent body/diff | other-review | Verdict: "correct, here is what I checked." Zero findings. Short output. |
| 6h | Body claims "no production impact" but diff touches production files | other-review | High-value finding: body ≠ diff contradiction |

## Test execution order

Run tests 1a–1f first (fast, no real PRs needed). Then 2a–2e (script mechanics). Then 3a–3f (shell traps + stash cycle). Then 4a–4e (forge detection — 4a–4c are automated against throwaway repos via `--repo`; 4e still needs a live GitLab setup). Then 5a–5d (routing integration). Then 6a–6h and the tighten overlay tests require real GitHub/GitLab data — schedule for a dedicated test session with controlled test repos.

## Known gaps (require real-world testing)

- **Inherited CI procedure**: Cannot fully test without access to multiple PRs on the same base. Requires a failing CI job and a second PR on the same base to verify control matching.
- **Council performance**: Distillation via council is async/background. Test requires an actual worklog task with substantial iteration history (>100 lines).
- **Token cost measurement**: Adversarial review on a large PR (~2000 line diff) needs profiling in production to calibrate depth budgets.
- **GitLab full path**: pr-query.sh's GitLab code paths are untested. Requires a GitLab instance with authenticated glab CLI and at least one open MR.
