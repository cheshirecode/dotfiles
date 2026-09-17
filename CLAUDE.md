# Repo rules and hard-won lessons

> Discipline specific to this checkout: commit hygiene, checkout and git
> safety, test discipline, and checks that have failed silently here before.
> Deliberately not a general guide to Claude Code or to software engineering
> — the harness ships that, and a local copy only drifts from it.

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

When the user targets `oss/dotfiles` (this checkout, wherever it lives),
use that primary checkout on `main` as the delivery surface and commit directly
to `main` unless the user explicitly asks for a branch or PR.

Default to a branch worktree for the work itself rather than editing the
primary checkout, and in a checkout another session may also be using, commit
before starting a long verification — a peer's reset destroys uncommitted work
mid-run.

Temporary agent worktrees under `.codex/worktrees/.../dotfiles` may be detached
or branch-prefixed by default. Treat them as scratch/integration surfaces only:
if work starts there, port or merge the exact changes back into the primary
`oss/dotfiles` checkout, validate from that checkout, and push `main` from
there. Do not let "detached HEAD" in a temporary worktree silently turn a
direct-main request into a side branch.

## Git safety (preconditions, not suggestions)

Never force-push to `main`, rewrite published history, or commit secrets or
large binaries. Review the diff before committing.

Conventional commit types used here: `feat`, `fix`, `refactor`, `test`, `docs`,
`style`, `perf`, `chore`, `ci`, `build`, `a11y`. Imperative subject, no trailing
period. One concern per commit; see commit hygiene above.

`git commit --amend` is for unpushed commits only. If
`git config --get branch.$(git branch --show-current).remote` returns a remote
AND `git rev-list @{push}..HEAD` is empty, the commit is already pushed. Do not
amend it.

`git reset --soft HEAD~1` undoes the last commit and keeps the changes. This is
the safe default for "undo my commit".

Never a bare `git commit` in a checkout another session may use: it writes
whatever a peer has staged. Use `git commit -- <path>`. If a partial commit
fails there (observed in a shared vault: `fatal: unable to read <sha>` for an
object that reads fine), build the commit on a temporary `GIT_INDEX_FILE` with
`read-tree`/`update-index`/`write-tree`/`commit-tree`/`update-ref`, which cannot
touch the working index at all.

Unstaging depends on which side the anomaly is on. A staged ADD of a path absent
from HEAD has nothing to restore, so `git rm --cached <path>` is the only correct
move; a staged DELETE of a path present in HEAD wants `git reset -- <path>`.
Check which case it is before reaching for either.

`git reset --hard HEAD~1` DISCARDS changes and is DANGEROUS. All three
preconditions must hold:

- The branch is unpushed (local commits would push). If pushed, use
  `git revert` instead.
- The user explicitly typed `--hard`. Do not infer it from "undo my commit";
  the soft form above is the default.
- The working tree is clean, OR the user explicitly accepts losing uncommitted
  work.

An agent reading this file as a checklist MUST refuse this command absent all
three. The same applies to `rm -rf` and force-push: establish the target and
the authority first.

## Test discipline

**Prove a new test red before shipping it.** Run it against the unfixed code,
confirm it fails, and confirm *which* assertions fail. A test that passes both
ways is worse than no test: it certifies the bug.

Match the intended record or behavior precisely. An assertion that matches a
summary instead of the target row can pass while the defect remains.

The recurring defect shape in this repo is **a pattern that matches something
adjacent to what was meant**:

- a greedy `sed 's/.*"state":"\([a-z]*\)".*/\1/p'` taking the *last* `"state"`
  in a one-line payload (a nested `author.state`) rather than the object's own
- `people/[a-z]+/active` failing to match any LDAP containing a dot
- a sort key whose `deprecated` term sat after `fit`, so retired models still
  outranked current ones — the test asserted only the top two and passed
- an unanchored `![0-9]{4}` matching the first four digits of five-digit refs
- a body cap applied to the `resume` branch while the adjacent `review` branch
  kept printing the same body whole — one caller of two, and the constant's
  `RESUME_` prefix made the omission read as deliberate
- an extension glob (`*.md`, `*.py`, `*.sh`) that skipped nine extensionless
  shebang scripts, so a new check could not see a defect in `bin/crew-radar`

All of them fail silent rather than loud, and a suite that only asserts "runs
clean" stays green while the tool is wrong. Measured cost of one instance: a
stale-ref checker reported 19 stale refs where the truth was 45, missing 58%
with no error surfaced.

Corollaries:

- **Prefer the silent failure when building a fixture.** If a wrong input can
  either 404 loudly or return a confident wrong value, build the fixture around
  the confident wrong value; the loud path proves much less.
- **A check nothing runs is not coverage.** Glob test directories in the runner
  rather than listing files, so a new fixture is wired up by existing.
- **Verify the red, not just its existence.** A broken fixture fails too, and
  its failure looks like proof. Read the error: if a red run ends in
  `ImportError`, `SyntaxError`, `TypeError` on a signature, or anything other
  than the assertion you meant to trip, suspect the fixture before believing
  the result. When restoring a baseline file to prove red, check what you
  wrote — `wc -l` and `head` it — before running anything.

  Measured 2026-09-15: `git show "$base:skills/worklog/bin/_task_context.py"`
  under zsh lost part of the path to a `:s/…/…/` history modifier, so the
  redirect truncated the target to zero bytes. The suite then failed with a
  confident `ImportError` that read exactly like a genuine red proof. Put the
  whole `rev:path` in one variable, or expand the path through a variable too.
- **Prove red on a copy, not by editing tracked files.** Reverting an
  implementation file in place races anything else reading the checkout, and a
  restore step that fails leaves the tree wrong. Copy the tree somewhere
  disposable, drop its `.git`, and mutate there — then a stray `git` command
  cannot reach the real repository at all.
- **One mutation, one assertion.** Revert or mutate a single file per run and
  record which assertion fired. A crash, an earlier assert, or a coupled test
  will otherwise hide the one you meant to prove — and a signature change
  crashes every test in the file, proving nothing about the behavior you
  changed. When the red arrives as a crash, follow it with a targeted mutation
  that keeps the interface and breaks only the behavior.

## Checks that fail silent

Every entry here is a check that stayed green while the thing it guarded was
broken. They share one shape with the defects above: the check measures
something adjacent to what was meant.

- **`pipefail` inverts a `linter | grep` gate.** `if linter | grep -q PATTERN`
  under `set -o pipefail` passes exactly when the linter *finds* problems, and
  fails when the code is clean. Capture the output and `test -n` on it instead
  of branching on a pipeline's status.
- **Quieting a check removes coverage. Classify, don't filter.** A carve-out
  must name one literal case. The moment it is a file, a glob, or a pattern
  class, it silently exempts everything later added to that class.
- **A diagnostic must separate absent from ok.** Four states, not two: ok,
  broken, absent, and unknown. Collapsing them lets a missing reader read as a
  passing one — and a zero-cost estimate is not an estimate, it is a lost rate
  table.
- **Assert what was consumed, not the wall clock.** A timed pipeline measures
  its slowest participant, so a wall-clock assertion passes or fails on the
  harness and the machine rather than on the change. Assert tokens, bytes,
  rows, or calls.
- **Per-mode CI hides composition bugs.** Running each mode in isolation and
  never the composed whole lets one section leak `set -e` and kill the combined
  run while every isolated mode stays green. Run the composition too.
- **Never print a secret to check it.** `${VAR:-placeholder}` expands to the
  *value* when the variable is set, so the guard behaves as an echo. Use
  `test -n`, or a hash prefix when comparing two values. Better, ask the tool
  that holds the credential (`gh auth status`) rather than the file storing it.
- **State a cited claim at its source's strength.** A recommendation restated
  as a limit, or one worked example restated as a general finding, reads as
  authoritative once the hedge is gone and no check can catch it. Measured
  2026-09-16: a drafted reference claimed guidance "caps a single response at
  25,000 tokens" where the source suggests "something like" that as
  manageable, and carried an invented "tenfold" with nothing behind it. Quote
  the hedge or attribute the example.
- **Verify from where a value is READ, not where it is SET.** An export placed
  in a parent scope, checked from that parent, passes while the consumer one
  directory down still sees nothing. Measured 2026-09-16: four org identifiers
  sat in `~/Documents/projects/.envrc` and verified there, but the clone that
  reads them had its own `.envrc` with no `source_up`, so the scrub stayed
  disabled where it mattered. Run the check from the consumer's cwd.
- **Do not infer behaviour from a filename.** A leftover `.loop_state.json.lock`
  read as "a stale lock blocks the next run". `state_lock` uses
  `fcntl.flock` on a descriptor, so the lock dies with the process and the file
  is inert; a non-blocking acquire succeeded immediately. Open the code that
  implements the name, even in your own repo.
- **Concurrent test runs agree for the wrong reason.** Two `tests/run.sh all`
  processes in one checkout share fixture temp paths, so a collision hits both
  identically and they report the same number. Agreement between overlapping
  runs is weaker evidence than one serial run, not stronger. Commit, then run
  once.
- **Re-measure before documenting a limitation.** "Cannot do X" ages into
  wrong, and no agreement pin catches prose. Re-run the check that established
  a limit before repeating it.

## Repo identity (public repo; enforced by a check)

These repos are public, so `cheshirecode` is the only account or org name that
may appear in tracked files. No employer org, no work account, no personal SSH
host alias — the `git@host-<owner>:` form names an owner too. Describe a hazard
by its shape rather than by a real name, and use placeholder owners in fixtures.

Real values live outside the repo: the per-clone `.envrc` supplies
`WORKLOG_ORG`, `WORKLOG_ORG_DOMAIN`, `WORKLOG_ORG_REPOS` and
`WORKLOG_FORGE_NAMESPACE`. Unset is REPORTED, never silently skipped.

Two traps, both hit on 2026-09-16:

- **Some occurrences are load-bearing.** The org literal in a deny pattern, a
  sanitizer, or that sanitizer's corpus IS the thing being matched; deleting it
  disables the guard. Parameterise instead, and check `git check-ignore`,
  defaults and tests before touching any literal.
- **A history rewrite does not scrub authors.** `--replace-text` leaves author
  and committer metadata untouched. Enumerate
  `git log --all --format='%an <%ae>'` and fix with `--mailmap`. On GitHub,
  `refs/pull/*` is read-only and survives a rewrite; only delete-and-recreate
  clears it.

`tests/run.sh static` enforces the account-name half of this.

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

Destructive commands (`git reset --hard`, `rm -rf`, force-push) carry explicit
preconditions in the git-safety section above. Honor them as preconditions, not
as advice to skip past.

## Search tooling

`zg` (zvec-grep) replaces bare `rg` for shell searches here. Read
[docs/search-tooling.md](docs/search-tooling.md) before using it: the exit-code
difference from `rg` breaks `||` fallbacks, and the ranked lanes cannot express
"not here".

## Fable 5.1 prompt alignment

Adopted 2026-09-03 from the official guide ("Prompting Claude Fable 5.1",
platform.claude.com). The Claude Code harness already ships the guide's
autonomy/finish-the-whole-task, delivering-work, progress-update,
tool-batching, and compaction blocks — do NOT duplicate those here; a stale
copy would fight the harness's newer one. This file adopts the three
prompt-text items the harness does not carry:

**Scoped changes and tests** (guide text, verbatim):

> If, while working or testing, you find a pre-existing bug, a performance
> concern, or behavior the task doesn't mention, don't fix, optimize or
> extend it in this change unless the requested behavior cannot work without
> it; report it as a follow-up in your summary. Where the task is ambiguous,
> implement the reading its wording and the surrounding code most directly
> support, state that assumption in your summary, and don't build for the
> other readings as well. Verify your work however you like; scratch scripts
> and quick checks need not be kept. Commit tests only where the task asks
> for them or this repository already keeps tests for this kind of change,
> sized like the neighboring test files — roughly one focused test per stated
> behavior — and don't turn scratch checks into additional permanent test
> files. This is about extras only: implement every behavior the task asks
> for, completely.

**Targeted edits over whole-file rewrites** (verbatim):

> The number of tokens used to edit files is best minimized, all else being
> equal. Therefore, when it will not affect the end result, try to surgically
> edit a file rather than rewrite the entire thing.

**Search before answering from familiarity** (verbatim):

> When a query centers on a name you do not confidently recognize, or
> recognize from a fast-moving area like AI models and developer tools where
> the landscape shifts within months, the name itself is the thing to verify:
> search before answering, and include the name as the user wrote it in at
> least one query alongside any reformulations. This holds even when you have
> some background on it — partial background is exactly what makes an
> out-of-date answer sound authoritative, so familiarity is not a reason to
> skip the search.

