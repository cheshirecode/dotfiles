## Resolve the skill directory

Resolve `<skill-dir>` to this `SKILL.md`'s directory (usually the load path). When unsure, run your host's line — tests/test_skill_dir_resolvers.py executes each one:

```bash
# Claude Code (empty when absent — never a bogus "./.."):
SKILL_DIR="$(f=$(find -L ~/.claude/skills -name loop_state.py -print -quit 2>/dev/null); [ -n "$f" ] && dirname "$(dirname "$f")")"
# Codex:
SKILL_DIR="$(for r in ~/.agents/skills ~/.codex/skills; do f=$(find -L "$r" -name loop_state.py -print -quit 2>/dev/null); [ -n "$f" ] && { dirname "$(dirname "$f")"; break; }; done)"
# Cursor:
SKILL_DIR="$(f=$(find -L ~/.cursor/skills -name loop_state.py -print -quit 2>/dev/null); [ -n "$f" ] && dirname "$(dirname "$f")")"
# Opencode / git worktree (empty unless the repo really carries the skill):
SKILL_DIR="$(r=$(git rev-parse --show-toplevel 2>/dev/null); [ -d "$r/skills/loop-engineering" ] && printf '%s' "$r/skills/loop-engineering")"
# Fallback — roots checked in order (a parallel find races -quit across roots):
SKILL_DIR="$(for r in ~/.claude/skills ~/.agents/skills ~/.codex/skills ~/.cursor/skills ./skills; do f=$(find -L "$r" -name loop_state.py -print -quit 2>/dev/null); [ -n "$f" ] && { dirname "$(dirname "$f")"; break; }; done)"
```
