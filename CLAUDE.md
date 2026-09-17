# Repo rules and hard-won lessons

> Discipline specific to this checkout: commit hygiene, checkout and git
> safety, test discipline, and checks that have failed silently here before.
> Not a general guide to Claude Code or to software engineering — the harness
> ships that, and a local copy only drifts from it.

<!-- Append new entries at the END. Caching matches a prefix, so an edit
     invalidates from its line onward; the two growing lists sit last for that
     reason and tests/run.sh static enforces it. -->

## Commit hygiene

One concern per commit. When work touches both guidance text (this file,
README) and behavioural guards (bin/*.sh, manifest, hooks), split them: the
diff lenses differ. Past anti-pattern kept as the reason: `98cd75f` bundled a
posture preamble with `git reset --hard` preconditions. Retroactive rebase and
force-push were judged net-negative; corrections live forward.

## Checkout and branch discipline

When the user targets `oss/dotfiles`, commit directly to `main` on that
checkout unless they ask for a branch or PR. Prefer a worktree for the work
itself, and in a checkout another session may use, commit before a long
verification — a peer's reset destroys uncommitted work mid-run.

Temporary agent worktrees (`.codex/worktrees/**`) are scratch only. Port work
back into the primary checkout, validate there, and push from there. A detached
HEAD in a scratch worktree must not turn a direct-main request into a branch.

## Git safety (preconditions, not suggestions)

Never force-push `main`, rewrite published history, or commit secrets or large
binaries. Review the diff first.

Conventional types: `feat` `fix` `refactor` `test` `docs` `style` `perf`
`chore` `ci` `build` `a11y`. Imperative subject, no trailing period.

`git commit --amend` is for unpushed commits only: if
`git config --get branch.$(git branch --show-current).remote` returns a remote
and `git rev-list @{push}..HEAD` is empty, it is already pushed — do not amend.

`git reset --soft HEAD~1` is the default for "undo my commit".

`git reset --hard HEAD~1` DISCARDS work. All three must hold: the branch is
unpushed (else `git revert`); the user explicitly typed `--hard`; the tree is
clean or they accept losing it. Absent all three, refuse. Same for `rm -rf` and
force-push: establish target and authority first.

Never a bare `git commit` in a checkout another session may use — it writes
whatever a peer staged. Use `git commit -- <path>`. If a partial commit fails
there (seen: `fatal: unable to read <sha>` for an object that reads fine),
build it on a temporary `GIT_INDEX_FILE` with
read-tree/update-index/write-tree/commit-tree/update-ref.

Unstaging depends on which side the anomaly is on: `git rm --cached <path>` for
a staged ADD absent from HEAD (nothing to restore), `git reset -- <path>` for a
staged DELETE present in HEAD.

## Reading posture

This is guidance, not a runnable checklist. Apply first: **Think before
coding** (surface assumptions; ask when readings differ), **Simplicity first**
(minimum diff, no speculative abstraction), **Surgical changes** (every changed
line traces to the request), **Goal-driven execution** (every step carries a
verifiable check; never claim done without citing a command's exit code).

Destructive commands carry preconditions in the git-safety section above. Honor
them as preconditions, not as advice to skip past.

## Search tooling

`zg` (zvec-grep) replaces bare `rg` for shell searches here. Read
[docs/search-tooling.md](docs/search-tooling.md) first: the exit-code
difference from `rg` breaks `||` fallbacks, and the ranked lanes cannot express
"not here".

## Machine-local secrets

One file per machine: `~/.env.secrets`, dotenv format, mode 0600, generated
empty by `install.sh` from `templates/env.secrets.example`. Read one key with
`bin/env-secret.sh KEY`, or hand one key to one command with
`bin/with-secrets.sh KEY -- cmd`. Read
[docs/machine-local-secrets.md](docs/machine-local-secrets.md) before adding a
credential anywhere else.

Never source the file globally. `.envrc` gives each directory tree its own
identity, so a credential exported in a login shell reaches every tree,
including work checkouts.

`.shell_common.*` is ignored as a class and must never be tracked; every
suffixed variant is machine-local by definition. `.shell_common` itself stays
tracked.

**A tool shell has no direnv, so `gh` uses the machine-wide token whatever
directory it names.** `direnv` only exports through its shell hook. A
non-interactive `bash -c` from a hook, an agent tool call or an MCP server
loads no `.envrc`, so the per-tree `GH_TOKEN` is absent and the inherited
`GITHUB_TOKEN` wins — the work account, inside a personal checkout. Wrap it:
`direnv exec . gh <args>`. `gh auth status` reporting the right account in an
interactive terminal proves nothing about the shell a tool runs in.

## Fable 5.1 prompt alignment

The harness already ships the autonomy, delivering-work, progress-update,
tool-batching and compaction blocks — do not duplicate them here. Three items
it does not carry are adopted verbatim in
[docs/fable-alignment.md](docs/fable-alignment.md): **Scoped changes and
tests**, **Targeted edits over whole-file rewrites**, and **Search before
answering from familiarity**.

## Repo identity (public repo; enforced by a check)

`cheshirecode` is the only account or org name allowed in tracked files. No
employer org, no work account, no personal SSH host alias (`git@host-<owner>:`
names an owner). Describe a hazard by shape; use placeholder owners in
fixtures. Real values live in the per-clone `.envrc`: `WORKLOG_ORG`,
`WORKLOG_ORG_DOMAIN`, `WORKLOG_ORG_REPOS`, `WORKLOG_FORGE_NAMESPACE`,
`WORKLOG_IDENTITY_DOMAIN`. Unset is reported, never silently skipped.

- **Some occurrences are load-bearing.** The literal inside a deny pattern, a
  sanitizer, or its corpus IS the match; deleting it disables the guard.
  Parameterise, and check defaults and tests before touching any literal.
- **A history rewrite does not scrub authors.** `--replace-text` leaves author
  and committer metadata untouched — enumerate
  `git log --all --format='%an <%ae>'` and fix with `--mailmap`. On GitHub
  `refs/pull/*` is read-only and survives a rewrite; only delete-and-recreate
  clears it.

`bin/leak-guard.sh` enforces the account-name and home-path half:
`--tree` in the suite, `--staged` in the pre-commit hook.

## Test discipline

Match the intended record precisely. An assertion matching a summary instead of
the target row passes while the defect remains. The recurring defect shape is
**a pattern that matches something adjacent to what was meant**:

- a greedy `sed 's/.*"state":"\([a-z]*\)".*/\1/p'` taking the *last* `"state"`
  in a one-line payload rather than the object's own
- an unanchored `![0-9]{4}` matching the first four digits of five-digit refs
- a body cap applied to `resume` while the adjacent `review` branch printed the
  same body whole; the constant's `RESUME_` prefix made it read as deliberate
- extension globs (`*.md`, `*.py`, `*.sh`) skipping nine extensionless shebang
  scripts, so a new check could not see a defect in `bin/crew-radar`

All fail silent, and a suite asserting only "runs clean" stays green while the
tool is wrong. Measured cost of one: a stale-ref checker reported 19 stale refs
where the truth was 45, missing 58% with no error surfaced.

- **Prove a new test red before shipping it.** Run it against unfixed code and
  confirm *which* assertions fail. A test that passes both ways certifies the bug.
- **Prefer the silent failure when building a fixture.** If a wrong input can
  404 loudly or return a confident wrong value, build around the latter.
- **A check nothing runs is not coverage.** Glob test directories in the runner
  so a new fixture is wired up by existing.
- **Verify the red, not just its existence.** A broken fixture fails too, and
  its failure looks like proof. `ImportError`, `SyntaxError` or a signature
  `TypeError` means suspect the fixture. Measured: under zsh,
  `git show "$base:path"` lost part of the path to a `:s/…/…/` history
  modifier and truncated the target to zero bytes, producing a confident
  `ImportError` that read like a genuine red. Put the whole `rev:path` in one
  variable.
- **Prove red on a copy, not by editing tracked files.** Copy the tree
  somewhere disposable, drop its `.git`, mutate there — then a stray `git`
  command cannot reach the real repository.
- **One mutation, one assertion.** Revert or mutate one file per run and record
  which assertion fired. A signature change crashes every test in the file and
  proves nothing about behaviour; follow a crash with a targeted mutation that
  keeps the interface.

## Checks that fail silent

Each stayed green while the thing it guarded was broken, sharing the shape
above: the check measures something adjacent to what was meant.

- **`pipefail` inverts a `linter | grep` gate.** Under `set -o pipefail`,
  `if linter | grep -q PATTERN` passes exactly when the linter finds problems.
  Capture the output and `test -n` on it.
- **Quieting a check removes coverage. Classify, don't filter.** A carve-out
  must name one literal case; a file, glob or pattern class silently exempts
  everything later added to it.
- **A diagnostic must separate absent from ok.** Four states: ok, broken,
  absent, unknown. Collapsing them lets a missing reader read as a passing one.
- **Assert what was consumed, not the wall clock.** A timed pipeline measures
  its slowest participant, so the assertion turns on the harness. Assert
  tokens, bytes, rows or calls.
- **Per-mode CI hides composition bugs.** One section leaking `set -e` kills
  the combined run while every isolated mode stays green. Run the composition.
- **Never print a secret to check it.** `${VAR:-placeholder}` expands to the
  value when set, so the guard is an echo. Use `test -n`, or ask the tool that
  holds the credential (`gh auth status`).
- **State a cited claim at its source's strength.** A recommendation restated
  as a limit, or one worked example restated as a general finding, reads as
  authoritative once the hedge is gone. Measured: a reference claimed guidance
  "caps a single response at 25,000 tokens" where the source suggests
  "something like" that, and carried an invented "tenfold".
- **Verify from where a value is READ, not where it is SET.** An export in a
  parent scope, checked from that parent, passes while the consumer one
  directory down sees nothing — a clone whose own `.envrc` lacked `source_up`
  left the org scrub disabled. Run the check from the consumer's cwd.
- **Do not infer behaviour from a filename.** A leftover
  `.loop_state.json.lock` read as blocking; `state_lock` uses `fcntl.flock` on
  a descriptor, so the file is inert and a non-blocking acquire succeeds.
- **Concurrent test runs agree for the wrong reason.** Two suites in one
  checkout share fixture temp paths, so a collision hits both identically.
  Commit, then run once.
- **Re-measure before documenting a limitation.** "Cannot do X" ages into
  wrong, and no agreement pin catches prose.
- **Never key a check to a value that drifts on its own.** A literal count, a
  hardcoded total, a `file:line` coordinate: each is a second copy of a fact,
  and the copy goes stale silently while the check keeps reporting. Key on
  something the subject itself carries — compute the count, match a marker in
  the source, assert the exit code. Then add the inert-lane guard: fail when
  *fewer* cases ran than expected, because a lane that stops running its cases
  otherwise reports a pass. Three measured instances in one day, 2026-09-17:
  a packages lane grepped for the literal `"e2e: 5 pass, 0 fail"` and turned
  red when the suite grew to 11 checks (`3f2a92e`); a sandbox test labelled
  itself `"8 cases"` while running 9; and commit-pathspec exemptions keyed by
  `file:line` broke on the first unrelated edit, reporting two healthy sites
  as violations while the two real exemptions silently lost their cover — that
  one was caught pre-ship by the guard's own anti-rot assertion firing, not by
  review, which is the outcome the rule is asking you to design for.
