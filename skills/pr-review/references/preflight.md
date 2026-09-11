## Detect platform and auth

```bash
# Resolve this skill's bin/ directory. `$0` would be the agent's own shell, not
# this skill -- SKILL.md is read, never executed.
BIN="<skill-dir>/bin"

"$BIN/detect-forge.sh" [--repo <clone-dir>] [--token <val>]
# stdout: forge<TAB>slug<TAB>cli<TAB>reason   (always four fields)
#   forge  = github | gitlab | other
#   cli    = gh | glab | ""
#   reason = empty on success, else gh-not-installed / gh-not-authenticated /
#            glab-not-installed / glab-not-authenticated / unsupported-forge-host
# exit: 0 usable · 2 usage error (not a repo, no origin) · 3 forge known but unusable
```

Exit 3 and exit 2 are different problems. Exit 3 means "this is GitLab and
`glab` is missing" — install it. Exit 2 means "I cannot tell what this is" —
check the remote. Reporting one as the other sends the user to fix the wrong
thing.

Then check ownership:

```bash
"$BIN/owner-check.sh" <n> [--repo <dir>] [--token <val>]
# stdout: self|other   exit: 0=self · 1=other · 2=error
```

Exit 1 is a verdict, not a failure — capture the status rather than letting
`set -e` abort on "other". Every failure resolves to exit 2, never to a default
of "self": guessing "self" is the costly direction, because it lets this skill
edit a PR that is not yours.

- exit 0, "self" → **self-check** (lightweight, may edit in place)
- exit 1, "other" → **other-review** (adversarial, report-only, never post without approval)
- exit 2, no output → **other-review**, and say in the output that ownership was
  unresolved and why. The script prints nothing on error, so treat "no output"
  as unknown, never as "self".

If `isDraft` is true:
- self-check: warn that review/tighten is premature; still run leak-scan
- other-review: structural audit only (leaks, stale title), skip deep code review

Closed or deleted PRs:
- `pr-query.sh view` may fail or return limited data. If PR is inaccessible, report "could not determine" and stop — do not guess from main.
- A deleted-but-historically-accessible PR: treat as other-review (read-only analysis), flag that some data may be missing.

## Common preflight (both entry points)

These apply before either review or closeout:

1. **Verify the PR identity and current diff with the forge CLI.** Record head/base
   branch names, head/base SHAs, state, draft status, creation time, and whether the
   diff is non-empty. `pr-query.sh view` omits some of these fields; use `gh pr
   view <n> -R "$slug" --json headRefName,headRefOid,baseRefName,baseRefOid,state,isDraft,createdAt` or the
   equivalent GitLab MR fields. Use the actual target branch head for base
   identity, not merely its merge-base. Resolve missing identity before reuse.
2. **Set up a local checkout only when needed** for source inspection, edits,
   tests or browser validation. Fetch and verify the actual head and target refs
   first. Preserve unrelated work; use a separate worktree when operations would
   disturb it. Forge-only review does not require checkout or dependency setup.
3. **When ancestry or inherited-CI analysis needs a merge-base**, compute it
   against the verified target using `git merge-base "$base_ref" "$head_sha"`,
   or equivalent verified forge evidence. Do not use `pr-query.sh merge-base`
   for this: it resolves the repository's default branch, which may differ from
   this PR's target. Read the forge diff as the review scope.
4. **Collect title, body and added diff lines for the selected mode.** Capture
   fetch status; missing data is not a clean result. Review applies
   [title-body.md](title-body.md) immediately; closeout applies it at step 3,
   after distillation and codification. Keep preflight read-only.

## Evidence collection and reuse

Keep one compact evidence index in the parent and raw diff/metadata in a unique
system temporary directory. Bind it to forge, repository, PR/MR number, head/base
SHAs and ref names, reviewed file scope, and the saved diff's SHA-256.

Only the diff may be reused: fresh identity and scope must match that key, and
the saved bytes must still match their hash. Missing or mismatched evidence
requires a new diff. Refresh ownership, title/body, state/draft status and CI on
each collection and before a final verdict or authorized write. Recheck identity
after collection; if it moved, discard the mixed snapshot and recollect.

If delegation is warranted and available, give bounded read-only delegates stable
instructions plus small packets containing the objective, file scope and evidence
paths. Load only applicable domain guidance; children must not each refetch the
forge. The parent owns integration, final freshness and all writes. Instruction
bytes and CLI counts are measurements, not proof of model-token or cache savings.

## Verification traps (other-review; remember for self-check too)

These all exit 0 and still lie. In self-check, apply selectively based on risk.

- **Silenced errors.** `cmd ... 2>/dev/null | wc -l` turns permission errors into `0`. Never build an absence claim on silenced output.
- **Masked exit codes.** `cmd | tail -3; echo $?` reports tail's status. Capture the status of the command you care about.
- **Stale CI views.** Identify CI by exact head SHA, workflow, and run attempt,
  not by check name alone. A newer successful run at the same head can supersede
  a cancelled predecessor only when the actual jobs and artifacts prove that
  relationship. Unrelated current runs and current failing attempts still count.
- **Mutation behind dry-run labels.** A `--dry-run` flag is not a read-only
  guarantee. Before and after Graphite planning or submission, snapshot relevant
  refs and worktree dirt. Do not execute a forbidden mutation merely to test the
  label, and never revert changes you do not own.
- **Local toolchain drift.** Check pinned runtime version against what you're running before reporting a failure.

## Confidence labeling

Every finding carries one label:

- **"I verified X"** — ran a command and read the output.
- **"I believe X, unverified"** — reasoning only. Say so explicitly.
- **"I could not determine X"** — respectable answer. Do not bluff past it.

Never smooth over the gap between these three.

## Inherited red CI

A failing check is not automatically the PR's fault.

1. Find the PR's merge-base.
2. Check whether the same job fails on the base itself.
3. Find a control: another PR on the same base, and one on an older base. If the failure tracks the base, it is inherited.
4. Read the actual error. If the failure *shape* differs between the PR and the control, say so rather than picking the convenient conclusion.

Blaming an author for someone else's breakage costs them a day. So does waving through a real regression.
