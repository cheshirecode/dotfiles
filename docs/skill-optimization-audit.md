# Skill optimization audit — 2026-09-11

Historical first-pass report. The subsequent conditional-loading rework and
current measurements are in [skill-token-design.md](skill-token-design.md).

Baseline: `origin/main` at `804f99930f16fa8e3161b38bdeaeca580871e586`.
`git pull --ff-only origin main` reported already up to date. Work is local on
`codex/skills-token-audit` in the isolated Codex worktree.

## Scope and evidence

Reviewed all 15 `skills/*/SKILL.md` entrypoints, their routing/dependency
boundaries, relevant references, and existing contract checks. This is an
instruction and loading-cost audit, not a line-by-line audit of every helper.

The sibling Worklog clone was read at `936fab48f631de83a4a774a9e3fc45a6c1108569`.
These task records informed the changes:

- `skill-lazy-loading`: keep cold safeguards, measure bytes/words separately
  from runtime tokens, and avoid splitting a workflow that needs every part.
- `harness-token-delegation-optimization`: reduce repeated context and avoid
  shell quoting retries; historical model prices were not reused.
- `agentic-fullstack-runbook`: narrow source changes and preserve fixture scope.
- `script-portability-gate`: validate from a path with spaces on Linux as well
  as native macOS. This task belongs to another repo; it supplied a test case,
  not an instruction to modify that repo.

Worklog's `modes/context.md` and context projection fixtures provide current
host-aware tracker behavior. The old preamble duplicated it with unconditional
Claude `TaskCreate` instructions and a full-kernel-cache suggestion. It now
routes to the current owner and uses `--tracker=none` when unavailable.
Durable-context guidance also distinguishes local-only work from remotely
recoverable artifacts and does not imply authorization to publish.

## Decisions and entrypoint size

Counts include frontmatter and use whitespace-delimited words. The total is
an inventory sum, not an assertion that every skill loads in one invocation.

| Skill | Before words | After words | Decision |
| --- | ---: | ---: | --- |
| brainstorm | 678 | 678 | Keep: council owns voting; distinct seed/novelty/round rules remain local. |
| council | 2,010 | 1,868 | Remove repeated Worklog, stage execution, and voter-count explanations; retain voting formula, vetoes, quorum, validation, and independence. |
| evidence-gate | 342 | 342 | Keep: compact router, typed evidence, and truthful-interpretation boundary. |
| example-led-instructions | 522 | 522 | Keep: short gate and one filled contract clarify the brittle output format. |
| job-application | 839 | 839 | Keep: evidence sourcing, fit assessment, artifact manifest, and manual-upload boundary serve one linear workflow. |
| karpathy-guidelines | 618 | 530 | Merge repeated clarification advice and shorten blocker definitions; preserve falsifier/replay and contradiction rules. |
| loop-engineering | 1,813 | 1,600 | Shorten composition table and repeated driver/state explanations; preserve tested cold safeguards. Durable-context reference delegates environment/tracker detail to Worklog. |
| loop-helpers | 610 | 610 | Keep: separate pack/transport gates and explicit byte-preserving fallback; standalone installation needs its own resolver. |
| pr-cost | 222 | 222 | Keep: short route-only entrypoint with ledger and posting boundaries. |
| pr-review | 237 | 237 | Keep: shared preflight and review/closeout routes already replace repeated procedures. |
| serena-rg-search | 583 | 472 | Remove generic search introduction and package-manager catalogue; retain measured zg caveats and capability fallback. |
| ship-hygiene | 1,079 | 863 | Merge duplicate surface lists, pairings, and anti-patterns into procedure/boundaries; retain checkpoint guard and pre-merge teardown prohibition. |
| tightening-a-pr | 109 | 109 | Keep: compatibility alias preserves existing callers without copying the implementation. |
| which-model | 589 | 589 | Keep: conditional routes already separate catalog work; tested resolver covers independently installed payloads. |
| worklog | 740 | 740 | Keep root router. Replace stale Claude-only preamble hydration and full-cache suggestion with the existing host-aware context owner. |

Total entrypoints: **10,991 → 10,221 words (7.0% less)** and
**76,315 → 71,406 UTF-8 bytes (6.4% less)**. Two conditional references also
shrank. These are structural proxies; no runtime token, latency, or cost
reduction is claimed without matched fresh-session telemetry.

No new reference tree or shared runtime dependency was added. Existing package
copies remain generated from the canonical skill; compatibility aliases and
self-contained resolvers remain because installations can be independent.

## Validation

- macOS `/bin/bash tests/run.sh all`: 158 pass, 0 fail during the audit.
- Final macOS static checks: 14 pass, 0 fail.
- Final loop-engineering Python suite: 106 tests pass.
- Final council wording preserves voter counts as a preference; its existing
  contract was rerun successfully on both platforms after that clarification.
- All 28 local links across the 15 roots and two edited references resolve.
- Existing Worklog compact-context request: `worklog-context/v1`, 825 bytes.
- Linux sandbox `/bin/bash tests/run.sh all`: 158 pass, 0 fail.

The first Linux run identified altered wording caught by existing skill
contracts. Tested cold guidance and explicit fingerprint flags were restored;
no tests were weakened. Its unrelated environment failures came from missing
fixture Git identity, an unpinned Ruff version, and PID-1 ancestry. The final
run uses CI's Ruff 0.15.12, disposable fixture identity, and Docker `--init`.

Linux runs use the sibling sandbox's `cheshirecode/sandbox:v1` image with
`--user dev`, no credentials, and a hashed source copy mounted at
`/tmp/skill audit`. This verifies Linux/Bash 5 and a space-containing path;
it does not establish Windows or every agent harness's behavior.

The package `worklog-memory-mcp` e2e lane is skipped when its optional
`node_modules` are absent; no changes touch that package. Raw run state,
source hashes, and logs are under `/tmp/dotfiles-skills-a639` and are transient.
The source changes and this report remain local and uncommitted. The shared
Worklog and primary dotfiles checkout were not edited.
