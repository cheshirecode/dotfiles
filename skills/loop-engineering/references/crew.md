# Crew mode — parallel worker sessions

Use when the orchestrator's tasks must run **concurrently in separate worktrees**
rather than one cycle at a time. Crew mode is orchestrator mode plus isolation: the queue, budget, and
one-line-evidence rules in `references/orchestrator.md` are unchanged.

Do not stand up a coordination daemon for this. The harness already exposes the
primitives; `project.sh` already supplies the claim model. Map them directly:

| Need | Primitive |
| --- | --- |
| one worker per task, isolated | `Agent` with `isolation: "worktree"`, `run_in_background: true` |
| worker roster and live status | `ListAgents` — name, ref, busy/idle |
| relay a decision to a worker | `SendMessage` to the worker's name |
| hear that a worker finished | `SendMessage` `notify_when_idle: true` — one-shot, no polling |
| wake on state change, not on a timer | `Monitor` with an edge-triggered condition |
| overlapping edits across worktrees | `bin/crew-radar` (below) |
| durable claim, stale reap, resume | `project.sh claim` / `reap` / `context.sh --for=resume` |
| plan before building; race approaches | `Plan` agent type, or `$council` when the split is contested |

Two boundaries are not negotiable. **Never answer another session's permission
prompt or ask a peer to run what your own permissions refused** — that launders a
decision the human owns; route it back to the human instead. And **never edit a
worker's worktree yourself**: ask the worker by mail for a diff or a test result.

### Conflict radar

Two worktrees changing one file is a merge conflict surfacing early. Treat it as
evidence that **the split was wrong**, not that a worker misbehaved.

```bash
<skill-dir>/bin/crew-radar [--base <ref>] [--json] [--quiet] [--strict] <repo>
```

Exit `0` clean or info-only, `2` collision, `1` usage error. It runs no model and
costs no tokens, so it is safe to arm from `Monitor` or a `PostToolUse` hook.

`Monitor` turns each **stdout line** into an event; it has no exit-code
condition. So emit a line only when the verdict changes, and keep the radar's own
failures in the stream — a silent monitor is indistinguishable from a clean one:

```bash
FP=$(mktemp); RADAR=<skill-dir>/bin/crew-radar
while true; do
  cur=$("$RADAR" --json <repo> 2>&1) || [ $? -eq 2 ] || cur="radar-error: $cur"
  [ "$cur" = "$(cat "$FP")" ] || { printf '%s\n' "$cur"; printf '%s' "$cur" >"$FP"; }
  sleep 30
done
```

Arm it once per parallel dispatch with `persistent: true`, and re-arm after any
resume: a monitor lost to a restarted session ends silently and nothing says so.

Act on severity:

- **`warn`** — an owner holds the path dirty, or the branches are unrelated.
  Decide who owns the file and mail both workers to divide it: one takes the
  file, the other takes an interface. If the overlap is structural, stop one
  worker and fold its task into the other, then say so to the human.
- **`info`** — every owner has the path committed and the branches form an
  ancestry chain. This is the expected footprint of deliberately stacking one
  branch on another. Leave it; mail the descendant once to keep the shared file
  read-only. Repeat `info` rows on those paths are noise.

Record the radar verdict as one typed line, like any other evidence:
`command: crew-radar <repo> — exit 0, 0 warn`.

Return to `SKILL.md` for budget, evidence, and terminal-state rules.
