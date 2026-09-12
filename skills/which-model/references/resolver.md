# Fallback skill resolver

Read only when the load path is unknown or the payload was flattened.

```bash
SKILL_ROOT=""
for d in "$PWD/skills/which-model" \
         "$HOME/.agents/skills/which-model" \
         "$HOME/.codex/skills/which-model" \
         "$HOME/.claude/which-model" \
         "$HOME/.claude/skills/which-model" \
         "${SUPER_RULER:-$HOME/.super-ruler}/.ruler/skills/which-model" \
         "/workspace/super-ruler/.ruler/skills/which-model" \
         "$HOME/super-ruler/.ruler/skills/which-model" \
         "$PWD/.claude/skills/which-model" \
         "$PWD"; do
  if [ -x "$d/bin/model-catalog" ]; then SKILL_ROOT="$d"; break; fi
done
echo "${SKILL_ROOT:-not found}"
```
