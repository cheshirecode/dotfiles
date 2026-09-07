---
name: pr-review
description: "Review a PR. One skill for all PR operations — two entry points: 'review' (code review with ownership-based modes) and 'closeout' (post-completion: council distill → codify triage → deslop → checkpoint). Triggers 'review PR #N', '/pr-review N', 'do a pr review', 'tighten up PR #N', 'wrap up this PR'. Replaces ship-hygiene per-PR ops and tightening-a-pr; ship-hygiene now delegates here."
---

# pr-review

One skill for all PR operations. Two entry points: **review** (code review) and **closeout** (post-completion retrospective).

## Detect platform and auth

```bash
# Resolve this skill's bin/ directory. `$0` would be the agent's own shell, not
# this skill -- SKILL.md is read, never executed.
BIN="$(f=$(find -L ~/.claude/skills ~/.agents/skills ~/.cursor/skills ./skills \
        -name detect-forge.sh -print -quit 2>/dev/null); [ -n "$f" ] && dirname "$f")"

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

1. **Checkout the PR branch at its tip.** Resolve to the PR's own branch first — never read files from main or a neighbor branch while reviewing a stack. A grep that succeeds in the wrong checkout looks identical to success in the right one.
2. **Recompute merge-base** before calling any diff line unexplained. The change you cannot account for is usually already merged.
3. **Run leak-scan** on the title, body, and diff. `leak-scan.sh` lives in
   `ship-hygiene/bin/` and owns the authoritative leak-token list:
    ```bash
    LEAK="$(find -L ~/.claude/skills ~/.agents/skills ~/.cursor/skills ./skills \
            -name leak-scan.sh -print -quit 2>/dev/null)"

    "$BIN/pr-query.sh" view <n> | jq -r '.title' | "$LEAK" --label body
    "$BIN/pr-query.sh" diff <n> | grep -E '^\+'  | "$LEAK" --label diff
    ```
    Exit 0 = clean, 1 = leaks found, 2 = usage or empty input. It refuses to
    call empty input clean, because a failed `pr-query` call and a leak-free PR
    produce the same zero bytes. Capture the status of the command you care
    about, not the pipeline's. Fix leaks in place for self-check; surface them
    for other-review.

    `pr-query.sh view` returns no `body` field. Fetch the body with the forge
    CLI directly when you need to scan it.

## Six verification traps (other-review; remember for self-check too)

These all exit 0 and still lie. In self-check, apply selectively based on risk.

- **Wrong checkout.** Same file differs on every branch in a stack. Resolve to PR's own branch tip.
- **Silenced errors.** `cmd ... 2>/dev/null | wc -l` turns permission errors into `0`. Never build an absence claim on silenced output.
- **Masked exit codes.** `cmd | tail -3; echo $?` reports tail's status. Capture the status of the command you care about.
- **Stale local main.** Recompute merge-base before calling anything unexplained.
- **Stale CI views.** Aggregated check summaries show failures from superseded commits. Read the actual failing job log.
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

---

# REVIEW entry point

Code review. Triggers: "review PR #N", "/pr-review N", "do a pr review".

Select mode via ownership detection (see above): self-check or other-review.

## Self-check mode (own PR)

Run this fast. Verify your own work without pretending to attack yourself.

**Depth budget:** ≤3 API calls total, no test execution, diff-size cap at 500 lines.

1. Checkout PR branch at HEAD. Re-verify at PR's current head — heads move.
2. Leak-scan title/body/diff (step 3 in common preflight). Fix in place.
3. Verify title describes final commit set:
    ```
    git log --format='%s' origin/main..HEAD | grep -oE '^[a-z]+\([a-z-]+\)' | sort | uniq -c | sort -rn
    ```
    Flag stale prefixes (`fix(preview):` when most commits are `perf(ci)`). Rewrite title if needed.
4. Body ≠ diff check: does the opening paragraph still describe everything this PR now contains? Quantified facts ("N tests", timeout values, TTLs) rot fastest; scope claims rot hardest. Correct in body, not in trailing comments.
5. Quick CI check: did the latest run pass? If not, verify inherited (abbreviated: just merge-base comparison + control PR on same base).
6. Verdict: **correct**, **correct with N fixable items**, or **blocked**.

Self-check may fix issues in place (edit files, amend PR body).

### Self-check output

```
=== self-check #N ===
Verdict: correct / correct with N items / blocked

Fixed:
  - <item> (<command>)

Flagged:
  - <item> (<evidence>)

What I checked:
  - <commands/runs>
```

## Other-review mode (others' PR)

Attack assumptions. Every finding must be verified. Manufacturing a finding is worse than missing one.

A clean PR gets: "this is correct, here is what I checked." Nothing more.

**Depth budget:** full battery — diff fetch, grep sweeps, stash+test cycle, CI status investigation.

### How to attack

- Find the load-bearing assumption — the one fact that, if false, makes the change wrong. Attack that first. Not style.
- For fixes: what invariant does this restore? What else writes to that invariant?
- For boundaries: do both sides agree (reader/writer, config/query)?
- For new tests: check whether the test **actually fails without the change**. Stash the patch, run test, restore. A passing test either way protects nothing.
- For constants/enums/config keys: check reachability. Unreachable branches hide silent misclassification later.
- Ask: second call, empty input, retry. Construct the interleaving that breaks concurrency/cache/ordering changes.
- Prefer one proven finding over five arguable ones.

### Scope discipline

- Review what the diff changes. Do not redesign the feature.
- A latent trap that the diff makes possible IS in scope. Say what would have to change for it to bite.
- Note adjacent problems as follow-ups. Do not fold them into this review.
- If the PR text claims something the diff contradicts — "not in this diff", "no production impact" — that is a finding. Often high-value, because reviewers rely on that text.

### Voice rules

Write simple technical English:

- Short sentences, ~20 words. One idea per sentence. Active voice.
- Plain facts. No idioms, no metaphor, praise padding, throat-clearing.
- Explain as if to someone new. Assume no context.
- Keep exact commands, paths, identifiers, error text unchanged.
- Cite `file:line` for every claim. Quote the line when short.
- State the consequence in user/operator terms, not just mechanism.
- No "great work", no "just", no "simply".
- Never summarize what the PR does.

Structure each finding: claim → evidence → consequence → smallest fix. Order matters.

### Output before posting

1. Re-verify every anchor at the PR's current head. Heads move.
2. Re-read each finding and strike any sentence you did not verify.
3. Drop findings that turned out wrong. Do not soften them into vague concerns.
4. **Get human confirmation before posting anything.** Inline comments only unless asked otherwise. Never post a summary comment by default. Never reply to a human reviewer as if you were the repo owner.

### Other-review output (to human, not posted to PR)

```
=== other-review #N ===
Verdict: correct / correct with findings / blocked

What I checked:
  - <commands/runs>

Findings:
  [HIGH] Claim — verified/unverified/could not determine
    Evidence: <command output + file:line reference>
    Consequence: <user/operator impact>
    Fix: <smallest correction>

  [MEDIUM] ...

Considered but dropped:
  - <finding>: <reason — e.g., "already fixed in commit X", "belongs to parent PR Y">
```

---

# CLOSEOUT entry point

Post-completion retrospective. Triggers: "tighten up PR #N", "wrap up this PR", "distill the learnings from this PR", "deslop this PR before handoff".

**Skip if:** trivial one-commit PR with no lessons worth codifying (do the deslop step alone). Implementation not actually finished → finish it first. No worklog task tracks this PR → skip step 4 (checkpoint).

Resolve `$WORKLOG_BIN` via `worklog/SKILL.md`.

## The pipeline (ordered — do not reorder)

The order is load-bearing: you distill learnings (step 1) **before** you compress the worklog (step 4) — compression drops the very iteration rows the learnings live in. You codify (step 2) **before** you checkpoint, so the codified changes and compressed worklog land as their own separate commits.

### 1. Distill learnings — via `council`

Dispatch `council` on the question: *"What are the durable, reusable learnings from PR #N — bugs whose class recurs elsewhere, missing reusable utilities, config that should be parameterized, guardrail gaps the work exposed?"* Feed it the worklog task body and the diff as context.

Why council and not a single read: a single agent transcribes the lessons that are already labeled and misses the ones that aren't. Council's independent angles surface blind spots, and its voting criteria are the exact filter you need next — `N-THRESHOLD-MET` answers "is this a recurring class worth a guardrail or an n=1 one-off", `SOLVES-EXTANT-PAIN` and `COST-PROPORTIONATE` gate speculative "might need it" learnings out.

Downgrade to a single-pass distillation only for a genuinely small PR — mirror council's own skip rule. Single-pass: read the worklog task body + diff once, ask yourself "what bug class, missing utility, or guardrail gap would the next agent re-discover?" and list them. Apply the same codify triage (step 2) to the list. Skip the voting machinery.

The output you carry forward is council's **kept list**: learnings that cleared the bar.

### 2. Codify each kept learning — triage, don't just note

For **every** kept learning, pick exactly one destination. "Note it in the PR description" is not a destination — that dies on merge.

| Learning shape | Codify as |
|---|---|
| Recurring class (council `N-THRESHOLD-MET` passed) — a bug pattern, a missing lint | **Durable guard**: extend an existing `bin/*.sh`/hook if one fits; add a new one only if none does. Behavioral. |
| A posture/discipline lesson ("split these commits", "verify before X") | **CLAUDE.md rule** or a skill edit. Guidance. |
| A concrete one-off fix/improvement, not yet recurring | **Worklog follow-up task** — a real `next_action` item, not a blocker for this PR. |
| Speculative / n=1 / no current consumer (council would REJECT) | **Drop it.** Don't manufacture infra for a hypothetical. |

Council gates whether a *learning* is kept — not its *destination*. Before writing a **new** script for a kept learning, confirm the destination decision itself clears `COST-PROPORTIONATE` / `NON-INFRA-PADDING`; an n≥3 bug class can still be a follow-up audit rather than a new guard if no cheap static check exists.

**Commit-hygiene split (per CLAUDE.md):** a guidance change (CLAUDE.md/README posture) and a behavioral guard (`bin/*.sh`, manifest, hooks) are separate concerns → separate commits, even in one session. Don't bundle a CLAUDE.md rule with a lint script.

### 3. Deslop the PR title/body + tracking tasks

This step absorbs the deslop logic from ship-hygiene and tightening-a-pr.

**3a. Title audit (critical — often skipped).** A valid Conv-Commit prefix is not a passing title: `fix(preview):` on a branch whose ten commits are mostly `perf(ci)` is a *stale* prefix. Re-derive the title from the final commit set:
    ```
    git log --format='%s' origin/main..HEAD | grep -oE '^[a-z]+\([a-z-]+\)' | sort | uniq -c | sort -rn
    ```
    Make the title describe the whole PR, leading with its largest change. **Do not edit titles on PRs older than 7 days** without explicit user confirmation.

**3b. Internal-ref leak scan.** Run both scans — they are not redundant (a worklog path in the diff is a leaked *code comment*; the same string in the body is a leaked *PR description*; a body under 5KB skips size flag but still needs this scan):
    - Title + body: pipe through `leak-scan.sh --label body`
    - Code comments (added lines only): pipe through `leak-scan.sh --label diff`
    `leak-scan.sh` owns the authoritative leak-token list. It exits 0 clean, 1 leaks found, 2 usage/refusal. It refuses to say "clean" over empty input because a failed `gh` call produces no bytes — indistinguishable from clean without capturing exit status.

    **Leak-token notes:** The token is `worklog:` (the trailer form), not bare `worklog`. The leaked forms include `Worklog:` trailer, task paths under `active/` **and `archive/`** (dotted/hyphenated/numeric LDAPs included), and the `worklog/<ldap>/<slug>` id form. Every sibling skill's command name is a token too. If the PR changes `skills/**` or skill docs: allow the relevant skill command names; still purge worklog paths, `next_action`, and agent-process chatter. Pure-engineering exception: technical framing is fine; internal-tooling chatter still goes.

**3c. Fix.** For title/body: **fix in place** — rewrite product-first, drop the internal refs. For code comments: surface and fix only if genuinely leaked process notes; keep durable why-comments.

**3d. Post-deslop checks (judgment — not covered by leak-scan).** A clean leak scan does not mean the deslop is done. These require judgment:

- **Body coherence:** Rewrite product-first (what changed for users + why) unless it's pure engineering/infra; skill command names are a leak *unless* the PR changes skill files. After any fix round that amends the branch, re-read the PR body for claims the amendment falsified — quantified facts (test counts, timeout values, TTLs) and absolutes ("never", "always", "no X anywhere") rot first, but the **scope** claim rots hardest. Re-ask "does the title, and the opening paragraph, still describe everything this PR now contains?", and a body that contradicts its own evidence comments burns reviewer trust. Correct in the body, not in a trailing comment.
- **Multi-stream synthesis:** A PR that grew a second stream tends to keep the first one's structure and bolt the rest on as `## Also: …` sections. That ordering encodes the order *you* did the work, not what the reviewer needs. Rewrite as one piece of work: open with what the PR delivers as a whole, order the sections by weight to the reviewer (largest or riskiest change first, regardless of which came first chronologically), and drop `Also:`/`Additionally:` framing. If the streams genuinely share no rationale, say so in one line near the top and still order by weight — do not leave the reviewer to infer it from section order. If they cannot be told as one story *and* the user has not asked for them together, propose splitting the PR, not papering over it with headings.

**3e. Evidence recording:** Record the current head SHA, the focused validation commands with pass/fail results, and the green CI run or check set in the PR body or a final PR comment. Keep "evidence complete" distinct from "ready for review": a draft PR is not ready until it is explicitly marked ready after those facts are current.

### 4. Compress + checkpoint the worklog

Compress the decided iteration drama out of the task body (drop ToT/Reflexion scaffolding, verified "Assumptions", multi-row iteration tables — git log is the audit trail; keep the decision rationale, lessons, re-runnable commands, `next_action`), then checkpoint it **on its own**: `"$WORKLOG_BIN/checkpoint.sh" <slug>`. Use the plain command — its staged-scope guard is exactly what enforces the single-concern commit. Keep this separate from step-2 codify commits — up to three concerns, up to three commits, never one bundle.

**No worklog task:** if step 1 was single-pass distillation from the diff + PR body alone (no worklog task tracks this PR), skip this step. The codify commits from step 2 and the deslop from step 3 are sufficient.

**Checkpoint hard failures:**
- **exit 1** — staged paths outside the slug's scope. Re-run with `--include=<path>` for each path that belongs with this slug, or `git restore --staged <path>` for the ones that belong to a different commit.
- **exit 2** — `--status=blocked` without a `Waiting on ...` next_action. Supply `--next="Waiting on <who or what>"`.

## Closeout output

```
=== distilled learnings (council) ===
  <N kept> / <M proposed>. Mode: <fg|bg>.
  - <learning> → <codify destination>

=== codified ===
  guard:    <bin/xxx.sh change> (commit <sha>)
  guidance: <CLAUDE.md rule>    (commit <sha>)
  task:     <next_action added to <slug>>
  dropped:  <n1 learnings, reason>

=== deslop ===
  #N title: <kept | rewritten: "<new title>"> (derived from <N> commits: <type counts>)
  #N body:  <single-narrative | restructured: dropped N "Also:" sections>
  Leak grep: <clean | fixed at ...>.  Scope re-check: <title+intro cover all streams | corrected>
  Evidence: SHA <hash>, validation: <cmds>

=== checkpoint ===
  <slug>: N → M lines. Commit <sha>. (separate from codify commits)
  [OR: skipped — no worklog task tracked this PR]
```

## Red flags — STOP, you're skipping a step

| Thought | Reality |
|---|---|
| "The lessons are obvious, I'll just list them in the worklog" | That's the baseline failure. Obvious-to-you lessons still evaporate uncodified. Run the distill + codify triage. |
| "Codifying is overkill for this" | Then council would have REJECTED the learning — drop it explicitly, don't skip the triage. |
| "I'll deslop the PR and call it done" | Deslop alone is ship-hygiene. You skipped distill + codify — the durable half. |
| "leak-scan came back clean, the body is fine" | It only checks internal references. It cannot see a stale title or a body that reads as two bolted-together streams. Steps 3a, 3d are judgment work no script reports on. |
| "The title has a Conv-Commit prefix, so it passes" | A prefix can be valid and stale. `fix(preview):` on a branch that is mostly `perf(ci)` describes one commit of ten. Re-derive it from the final commit set. |
| "I'll put the post-merge/cleanup note in the PR body" | Reviewer-facing text dies on merge. It belongs in the worklog. |
| "One commit for all of it is cleaner" | Guard + guidance + worklog are different diff lenses. Split them (CLAUDE.md commit-hygiene rule). |
| "I'll compress the worklog first, then find the lessons" | Compression drops the rows the lessons live in. Distill FIRST. |

## Anti-patterns

- Running adversarial review on your own PR pretending it's adversarial — self-check is a sanity pass, not a stress test. Don't burn tokens on performative criticism.
- Posting inline PR comments without human approval in other-review mode — you are flagging, not deciding.
- Manufacturing findings to look useful — a clean PR gets a short "this is correct, here is what I checked."
- Running full adversarial battery in self-check mode — respect the depth budget. Three API calls, no test execution.
- Treating a clean leak-scan as completing the deslop step — leak-scan checks internal references only. It has no opinion on title accuracy or body coherence.
- Bundling review findings with closeout deliverables into one commit — they serve different operators (reviewer vs author) and should land separately.
- Reviewing draft PRs at full depth — drafts haven't earned reviewer attention yet. Structural check only.
- Turning every learning into a follow-up task by default (the safe-looking option that codifies nothing durable).
- Running a heavyweight council on a trivial one-commit PR — downgrade to single-pass distillation.
- Running a full multi-PR CI/comment sweep — that's ship-hygiene's job, not this single-PR operation.
- Blind-editing 20 PR titles for stylistic consistency — Conv-Commit minor variations are not slop.

## Pairings

- `ship-hygiene` — the periodic multi-PR dashboard. Delegation runs one way:
  ship-hygiene calls `$pr-review` for each flagged PR, and pr-review never
  calls back. That one-way rule is what keeps the two from looping. ship-hygiene
  also owns `bin/leak-scan.sh`, which this skill uses directly.
- `tightening-a-pr` — DEPRECATED. A shim that runs this skill's closeout entry point. See below.
- `council` — used by closeout step 1 distillation. Not invoked by review modes directly.
- `worklog` — closeout step 4 checkpoint (`checkpoint.sh`); follow-up learnings become `next_action` items.
- `karpathy-guidelines` — apply during self-check ("don't refactor what isn't broken"). During other-review, review scope discipline ("do not redesign the feature").
- For brittle outputs, invoke `$example-led-instructions`: 0/1/few-shot gate, max 1-3 examples, skip if obvious.

## Tightening-a-pr shim (backward compatibility)

`tightening-a-pr` is a deprecated shim with no logic of its own. It loads this
skill, runs the **closeout** entry point, and relabels the output to its
original schema. `skills/tightening-a-pr/SKILL.md` is the only copy of that
contract — do not restate it here, or the two will drift.
