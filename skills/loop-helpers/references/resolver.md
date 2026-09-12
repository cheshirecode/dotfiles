# Fallback skill resolver

Run only when the load directory is unavailable. An empty result means absent.

```bash
# Roots checked in order; empty when absent — never a bogus "./..":
SKILL_DIR="$(for r in ~/.claude/skills ~/.agents/skills ~/.cursor/skills ./skills; do f=$(find -L "$r" -name context_pack.py -print -quit 2>/dev/null); [ -n "$f" ] && { dirname "$(dirname "$f")"; break; }; done)"
```
