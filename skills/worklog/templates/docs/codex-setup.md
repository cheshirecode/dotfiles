# Codex setup — worklog

Codex CLI / Codex App use the same `_worklog` repo as Claude Code. The task file format, slug grammar, and `$WORKLOG_BIN/*` helpers are all shared. The only differences are **how the skill is installed** and **what runs at session boundaries** — Codex has no equivalent of Claude Code's `PreCompact` / `SessionEnd` hooks.

## Install

1. **Clone** `_worklog` under `$PROJECTS_DIR/_worklog` (same as Claude — the repo is machine-shared).
2. **Install the Codex skill file**: install `~/.codex/skills/worklog/SKILL.md` from the exported setup artifact or the current machine's synced skill. It is Codex-native: same protocol and helpers as Claude, but a single-file command surface that maps tracker work to `update_plan` and documents Codex's no-hooks session-end flow.
3. **Verify MCP access** if you want tier-2 retrieval: serena's Codex integration is documented at [oraios/serena](https://github.com/oraios/serena). `rg` tier-1 works without any MCP setup.
4. **`rg --version`** succeeds (tier-1 retrieval; required for interactive grep).

## Compaction / session-end story (manual, not hooked)

Codex has no `PreCompact` or `SessionEnd` hooks equivalent. Two consequences:

- **Durable task state** won't auto-save before a conversation summary. Use prompt-level `/worklog sync <slug>` when you made meaningful task progress; use `"$WORKLOG_BIN/autosave.sh"` only as a slugless safety snapshot for uncommitted edits that do not yet have a clean checkpoint target.
- **Compact kernels** won't auto-dump. Run `"$WORKLOG_BIN/compact-kernels.sh"` manually before ending a session — it writes `.cache/compact-kernels.md` for the next session to pick up.

Recommended flow at session end:

```bash
cd $PROJECTS_DIR/_worklog
# In chat: /worklog sync <slug>
"$WORKLOG_BIN/checkpoint.sh" <slug>   # shell alternative when the exact save is known
"$WORKLOG_BIN/autosave.sh"            # optional safety snapshot if dirty worklog edits remain
"$WORKLOG_BIN/compact-kernels.sh"     # dump per-active-task resume kernels
```

On **session start** (Codex): read `_worklog/.cache/compact-kernels.md` first if it exists and is <1 hour old — one pass through ~7 lines per active task orients you across everything in flight. Then re-read the specific `people/<ldap>/active/<slug>.md` you're resuming. The task file is authoritative; the kernel is a signpost.

## Codex surface drift check

After editing `README.md`, `AGENTS.md`, or `~/.codex/skills/worklog/SKILL.md`, run:

```bash
cd $PROJECTS_DIR/_worklog
"$WORKLOG_BIN/codex-surface-check.sh"
```

The check only verifies command-menu parity across the repo docs and the local Codex skill. It is deliberately narrow: behavior still belongs to `AGENTS.md` and the helper scripts.

## Everything else

Read `_worklog/AGENTS.md` for protocol, `docs/protocol.md` for deep material, `docs/rag-format.md` for retrieval tiers (rg / serena / semantic cache), `docs/helpers.md` for the helper catalogue. The durable protocol and helpers are shared with Claude Code; the local skill surface differs where the host differs (`update_plan` instead of `TaskCreate`, manual compaction/session-end steps instead of hooks).
