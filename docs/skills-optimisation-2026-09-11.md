# Skills optimisation audit — 2026-09-11

Audited all 15 skill entry points against fetched `origin/main`
`24ef2d28fd3761b445e41319cf16944e2aaf5b6b`. This was the initial audit baseline. Ten entry points were shortened; five were retained. No new reference
files or skill dependencies were introduced.

## Design decisions

Historical task evidence informed three constraints: measure source size separately
from runtime token usage; preserve cold-invocation routing; and avoid splitting
linear workflows into references that every invocation must load. Repeated prose
was removed in place. Validation executes the documented resolver on native
macOS Bash 3.2 and the sibling sandbox image's Linux Bash 5.2.

## Entry-point inventory

Words are whitespace-delimited counts over the complete `SKILL.md`, including
frontmatter. These measure source size, not tokenizer output or runtime cost.

| Skill | Before | After | Decision |
|---|---:|---:|---|
| brainstorm | 678 | 678 | Keep: already delegates evaluation to council. |
| council | 2,104 | 2,010 | Deduplicate dispatch, template-loading and Worklog prose; keep voting invariants. |
| evidence-gate | 395 | 342 | Remove repeated activation list; retain coverage-versus-truth and digest limits. |
| example-led-instructions | 644 | 522 | Remove redundant workflow narration; retain gate, schema and compact example. |
| job-application | 839 | 839 | Keep: linear workflow and upload boundary need the existing detail. |
| karpathy-guidelines | 650 | 618 | Remove repeated activation prose; retain hypothesis and contradiction rules. |
| loop-engineering | 1,992 | 1,813 | Shorten metadata and repeated driver/orchestrator explanation; retain effect and terminal rules. |
| loop-helpers | 610 | 610 | Keep: transport caveats prevent false success and unsupported savings claims. |
| pr-cost | 222 | 222 | Keep: small conditional router with privacy and write boundaries. |
| pr-review | 237 | 237 | Keep small router; improve deferred procedures in the follow-up below. |
| serena-rg-search | 782 | 583 | Compress repeated triggers, measured caveats and tool-availability explanation. |
| ship-hygiene | 1,167 | 1,079 | Remove redundant examples; verify task relevance and shared CI cause before acting. |
| tightening-a-pr | 166 | 109 | Retain compatibility mapping; remove historical routing explanation. |
| which-model | 600 | 589 | Shorten metadata and repair payload selection. |
| worklog | 876 | 740 | Remove directory tree and duplicate preamble links; correct project routing. |
| **Total** | **11,962** | **10,991** | **971 fewer words (8.12%).** |

Total entry-point bytes: **82,912 → 76,315**, a **7.96%** reduction. Reference
payloads were not moved or duplicated. The Worklog project mode gained explicit
dry-run handling; the new resolver regression test is executed rather than
loaded as skill instructions. No runtime token-saving percentage is claimed.

## Correctness improvements

- `which-model` uses its loaded directory when the catalog payload exists.
  Its fallback checks the current repository, shared `.agents` installation and
  legacy `.codex` installation before the existing Claude/flattened paths.
  Five executable recipe tests cover conflicting copies, both Codex roots,
  flattened installations and missing payloads. The old recipe fails the first
  three relevant cases; the revised recipe passes all five.
- Worklog explicitly classifies `project add-child` as mutating. Supported
  `new`, `add-child` and `claim` dry runs skip preamble because even minimal
  preamble may create a namespace and full preamble may autosave. The project
  mode documents the actual `add-child` command and its preview flag. The helper
  may still refresh a temporary identity cache; this is not a zero-filesystem-write claim.
- Ship hygiene verifies a task's repo/PR relevance before compression. If no
  relevant task exists, cleanup notes stay in the report. Repeated CI check
  names require log evidence of a shared cause before being called systemic.

## Validation

These full-suite results cover the initial optimisation. The subsequent
`pr-review` reference-only follow-up has separate focused validation below;
the entry-point size measurements remain unchanged.

| Check | Result |
|---|---|
| macOS ARM64, Bash 3.2, Python 3.14, Node 25 | `tests/run.sh all`: 158 pass, 0 fail. |
| Ubuntu 24.04 ARM64, Bash 5.2, Python 3.12, Node 20 | `tests/run.sh all`: 158 pass, 0 fail. |
| Resolver regression | Old recipe: 3 failures; revised recipe: all 5 pass. |
| Independent instruction scenarios | Model guideline, project preview/write, unrelated-task hygiene and search-absence routes reviewed; ambiguities resolved. |
| Packaging | All 15 skills byte-checked in 3 temporary discovery roots (45 installations); fixture manifest redirects install destinations. |
| Source identity | Before the follow-up, all 297 skill files matched between host and Linux copy; all entry-point Markdown links resolved. |

Replay commands from the checkout:

```bash
/bin/bash tests/run.sh all
python3 skills/which-model/tests/test_skill_root.py
python3 tools/check-skill-opt-ins.py
/bin/bash bin/install-skills.sh --dry-run --include-optional
git diff --check
```

An installer dry-run from a different worktree can correctly refuse to replace
existing installed symlinks. Do not delete or repair them to obtain a green
check; use isolated installation destinations. The packaging proof above used
an unchanged installer and a fixture manifest with temporary `install_to` paths.

The suite skips the optional `worklog-memory-mcp` Node end-to-end check when its
dependencies are absent. This pass did not change that package or install its
dependencies. Static checks, skill fixtures and Worklog fixture-vault checks ran.

The Linux run uses `cheshirecode/sandbox:v1` from the sibling sandbox setup,
image `sha256:7b3f9fbddae485adbdfda80316677e361fa96b8a30399e0a22e81f7f745e5f97`,
Ubuntu 24.04 / ARM64, as `dev`. Source is mounted read-only and copied to a
temporary Git fixture; no host credentials or existing sandbox volumes are used.
Ruff is pinned to repository CI's `0.15.12`. Native Windows and agent-client
reference loading across all supported clients are outside this validation.

## PR-review procedure improvements

The deferred procedures now define when review evidence can be reused and when
local setup is required. These are instruction changes; collector performance
and runtime token savings have not been measured.

| Suggestion | Disposition |
|---|---|
| Parent evidence index and bounded diff reuse | Shared preflight: bind forge/repo/PR, head/base SHAs and refs, file scope and saved diff hash; refresh mutable metadata and check collection races. |
| Conditional local setup and honest call accounting | Documented: forge-only review needs no checkout/setup; local analysis verifies refs when required. CLI invocations and HTTP requests are separate metrics, with no hard three-call limit. |
| Stable delegate packets and conditional domain instructions | Compact packet guidance for warranted read-only delegation. Existing review/closeout routing stays. |
| Preserve regression fixtures | Replaced the stash recipe with isolated implementation-only rollback; test plan now checks the intended failing assertion and restored passing case. |
| Collector artifact-output guard | Deferred: dotfiles has no collector/output-directory feature to harden. If one is introduced, cover Git metadata, bare repositories and unexpected discovery errors before adopting it. |

The title/body procedure now shares preflight's reuse rules instead of allowing
scan reuse on a weaker head/title/body key. Commit-message evidence may come
from the forge; local `git log` requires verified refs and merge-base.

Only deferred guidance and its manual test plan changed. No collector, forge
adapter or skill entry point changed. The added freshness rules are not a claim
that fewer calls, tokens or cache misses have been measured in dotfiles.

Follow-up verification: isolated regression replay passed/fail-as-expected/passed
with unchanged test bytes. The 2 Python tests and 4 PR-review shell fixture scripts
passed on macOS and the sibling sandbox Linux image. Static checks passed 14/14;
`git diff --check` passed. The Linux fixture needed an initialized Git repository
because an existing merge-base test inspects the checkout containing the skill.
Independent review covered the five freshness/setup/regression scenarios and
confirmed the corrected title/body cross-references have no remaining contradiction.
