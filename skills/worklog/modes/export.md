# Mode: `export`

Emit a sanitized, self-contained setup prompt for the worklog system —
repo + local Claude/Codex skills + relevant agent settings/config —
with secrets masked and org/user identifiers scrubbed to placeholders.
Output lands at `/tmp/worklog-setup-<YYYYMMDD-HHMMSS>.txt`.

**Does not run the preamble.** No LDAP resolution, no repo pull, no
checkpoints. Pure export.

## Steps

1. Run `bin/export-setup.sh` (no args). It collects `AGENTS.md`,
   `README.md`, `docs/*.md`, `bin/*` (scripts only), both local worklog
   skill files, and the advisory agent settings/config surfaces
   (`~/.claude/settings*.json`, `~/.codex/config.toml`). Secrets get
   masked; org strings (`cheshirecode`, `@cheshirecode.ai`, known repos, LDAP,
   `/Users/<name>/`) get replaced with `<your-*>` placeholders.

2. **Memory distillation** (3 passes — judgment work, script skips it).
   Memory files under `~/.claude/projects/-Users-*-_worklog/memory/`
   are collected verbatim under "Section 4 — Memory templates (DRAFT)".
   You then edit the final `.txt` in place:
   - **Pass A — drop user-specific:** any memory whose entire content
     is personal (user's role, internal teammates, one-off incidents
     naming internal tools) → delete the whole `### FILE:` block.
   - **Pass B — generalize survivors:** rewrite specifics into
     placeholder form. "Fred works on ingestion" → "`<user>` works on
     `users.noreply.github.com`". Keep the structural lesson; strip the identifying
     detail.
   - **Pass C — residual sweep:** `grep -iE 'cheshirecode|cheshirecode|@users.noreply.github.com'`
     on the memory section. Any remaining hit → drop that memory or
     re-generalize. If empty dir on source, the script writes a
     `_(no memory files…)_` placeholder — leave it.

3. Verify deliverable:
   - File exists at reported path, non-empty, <500KB.
   - `grep -iE 'cheshirecode|cheshirecode|@cheshirecode\.ai'` → 0 hits.
   - Secret regex sweep (`sk-…{20,}`, `ghp_…{20,}`, `AIza…{35}`,
     `AKIA…{16}`) → 0 hits.
   - Section headers 1–4 + post-setup checklist all present.
   - If Codex is in use on the source machine, the artifact includes
     `~/.codex/skills/worklog/SKILL.md`.

4. Report to user: path + one-line summary (file count, byte size, any
   memory distillation actions taken). Do **not** dump the prompt
   inline.

## Boundaries

- Never include `people/` (user tasks — excluded by script), nor
  `config/teams.json` (team roster — excluded by script).
- Never abort on secret detection; the script masks in place. If the
  post-run residue check finds any unmasked secret, report it and let
  the user decide.
- Script is idempotent and side-effect-free outside `/tmp/`. Running
  it twice is fine.
