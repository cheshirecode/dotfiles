#!/usr/bin/env bash
# Export the worklog setup (repo + local skills + agent settings advisory)
# to a sanitized, self-contained LLM setup prompt at
# /tmp/worklog-setup-<ts>.txt.
#
# Scrubs org identifiers, user paths, and secrets. Excludes user tasks
# (people/<ldap>/*), team config (config/teams.json), and the git dir.
# Memory files are collected but NOT generalized here — the calling skill
# runs a 3-pass distillation in-session (judgment work).
#
# Usage:
#   bin/export-setup.sh            # writes /tmp/worklog-setup-<ts>.txt
#   bin/export-setup.sh --dry-run  # prints file list + scrub counts; no write

set -euo pipefail

# Note: emit_file PATH-header strings later in this file use literal `~/...`.
# That's intentional (the artifact's display paths are for the receiver to
# expand under their own $HOME). Run shellcheck with --severity=error to
# skip the SC2088 warnings on those lines.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1

LDAP="$(resolve_ldap)"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

TS="$(date +%Y%m%d-%H%M%S)"
OUT="/tmp/worklog-setup-${TS}.txt"
DRAFT="$(mktemp -t worklog-export.XXXXXX)"
trap 'rm -f "$DRAFT"' EXIT

CLAUDE_SKILL_SRC="$HOME/.claude/skills/worklog/SKILL.md"
CODEX_SKILL_SRC="$HOME/.codex/skills/worklog/SKILL.md"
SETTINGS="$HOME/.claude/settings.json"
SETTINGS_LOCAL="$HOME/.claude/settings.local.json"
CODEX_CONFIG="$HOME/.codex/config.toml"
MEM_DIR="$HOME/.claude/projects/-Users-${LDAP}-Documents-projects--worklog/memory"

# ---- scrubbing ---------------------------------------------------------------
# Mask secrets first (so org scrub can't accidentally unmask), then generalize
# org/user identifiers. Perl because BSD sed lacks `\b`.
#
# Regression tests: tests/export/test_scrubber.sh asserts that the secret
# patterns below do not over-match on a clean (secret-free) corpus. If you
# add a new secret pattern here, mirror it into tests/export/test_scrubber.sh
# and verify the clean corpus still survives untouched. See audit-prompt § 3.
scrub() {
  LDAP="$LDAP" perl -pe '
    s{sk-[A-Za-z0-9_-]{20,}}{<REDACTED:SECRET>}g;
    s{ghp_[A-Za-z0-9]{20,}}{<REDACTED:SECRET>}g;
    s{github_pat_[A-Za-z0-9_]{20,}}{<REDACTED:SECRET>}g;
    s{xox[abpros]-[A-Za-z0-9-]{10,}}{<REDACTED:SECRET>}g;
    s{AIza[A-Za-z0-9_-]{35}}{<REDACTED:SECRET>}g;
    s{AKIA[0-9A-Z]{16}}{<REDACTED:SECRET>}g;
    # 40-hex unprefixed token pattern removed: legacy GitHub PATs (deprecated
    # since 2021) were the only real-world hit; full git SHAs in commit
    # permalinks are the dominant clean-content collision. Modern secrets
    # (ghp_, github_pat_, sk-, AKIA, AIza, xox*) are all prefixed and caught
    # above. See tests/export/clean_corpus.txt for the regression fixture.
    s{[Ii]deogram(?:-[A-Za-z0-9._-]+)?(?=[^A-Za-z0-9]|$)}{<your-org>}g;
    s{\@ideogram\.ai}{\@<your-domain>}g;
    s{\b\Q$ENV{LDAP}\E\b}{<ldap>}g;
    s{/Users/[a-zA-Z0-9._-]+/}{~/}g;
    s{\b(?:Landing-Page|devops-permissions|website|ui)\b}{<your-repo>}g;
  '
}

emit_file() {
  # $1 = display path (target-relative), $2 = source path. Writes to stdout
  # so the single outer `> $DRAFT` redirect orders everything correctly.
  #
  # Sentinel-delimited multipart format so awk can reliably split out each
  # file on import. Avoids the ``` fence-collision bug that markdown fencing
  # had with files containing their own code fences.
  #
  # Content stream is normalized to exactly one trailing newline (via
  # "$(...)" + printf '%s\n') so importer round-trip is byte-identical for
  # POSIX-compliant files. Trade: files with trailing blank lines lose them,
  # which is the preferred tradeoff vs always-one-extra-blank.
  local target="$1" src="$2" content
  [[ -f "$src" ]] || return 0
  content="$(scrub <"$src")"
  printf '\n=====WORKLOG-EXPORT-FILE=====\n'
  printf 'PATH: %s\n' "$target"
  printf '=====WORKLOG-EXPORT-CONTENT=====\n'
  printf '%s\n' "$content"
  printf '=====WORKLOG-EXPORT-END=====\n'
}

# ---- assemble ----------------------------------------------------------------
{
  cat <<'PREAMBLE'
# Worklog system — bootstrap prompt

You are helping a user set up the `_worklog` system on a fresh machine.
The worklog is a git-synced journal of in-flight engineering work, plus
local Claude Code / Codex skills that drive it. This prompt contains
everything needed to reproduce the durable setup.

Placeholders to resolve with the user before writing files:
  - `<your-org>`      — GitHub org that will host the worklog repo
  - `<your-domain>`   — email domain used for LDAP resolution
  - `<your-repo>`     — primary code repo(s) the user works in
  - `<ldap>`          — shorthand user id (auto-resolved from gcloud/git)

Procedure:
  1. Confirm placeholders with the user.
  2. Create an empty GitHub repo `<your-org>/_worklog`.
  3. Clone it under `~/Documents/projects/_worklog` (or the user's
     projects dir).
  4. Land every file in the "FILE:" sections below at the indicated
     path, substituting placeholders.
  5. Install the skill files at `~/.claude/skills/worklog/SKILL.md`
     and `~/.codex/skills/worklog/SKILL.md` when those agents are in use.
  6. Apply the Claude Code settings deltas (merge keys; do not clobber
     existing settings.json unless the user confirms).
  7. Review the Codex config advisory section and merge only the stable
     pieces that make sense on the destination machine.
  8. Review the memory-template section and offer to seed
     `~/.claude/projects/<project-dir>/memory/MEMORY.md` from it.
  9. Run `bin/install-hooks.sh --write` from the worklog repo to wire
     PreCompact + SessionEnd autosave hooks.
  10. Post-setup checklist (end of this prompt) — run through it.

Values masked as `<REDACTED:SECRET>` were sensitive; do not attempt to
recover them.

## Artifact format

File contents are packed in sentinel-delimited blocks (NOT markdown
fences — markdown would collide with embedded ``` in the exported
files). Parse with awk or equivalent:

    =====WORKLOG-EXPORT-FILE=====
    PATH: <target-path>
    =====WORKLOG-EXPORT-CONTENT=====
    <raw file content>
    =====WORKLOG-EXPORT-END=====

On import:
  - Anything under `bin/` → `chmod +x` after write.
  - Placeholders (`<your-org>`, `<your-domain>`, `<your-repo>`, `<ldap>`)
    must be substituted with the importing machine's values before write.
  - Repo files + local skill files: auto-apply (LLM may merge markdown;
    accept/skip only for scripts).
  - Agent settings/config + memory sections: advisory only — do not
    auto-write.

---
PREAMBLE

  printf '\n## Section 1 — worklog repo files\n'
  emit_file "_worklog/.gitignore"              "$REPO_ROOT/.gitignore"
  emit_file "_worklog/README.md"               "$REPO_ROOT/README.md"
  emit_file "_worklog/AGENTS.md"               "$REPO_ROOT/AGENTS.md"
  for f in "$REPO_ROOT"/docs/*.md; do
    emit_file "_worklog/docs/$(basename "$f")" "$f"
  done
  for f in "$REPO_ROOT"/bin/*.sh "$REPO_ROOT"/bin/*.py; do
    [[ -f "$f" ]] || continue
    emit_file "_worklog/bin/$(basename "$f")"  "$f"
  done

  printf '\n## Section 2 — local agent skills\n'
  emit_file "~/.claude/skills/worklog/SKILL.md" "$CLAUDE_SKILL_SRC"
  for f in "$HOME"/.claude/skills/worklog/modes/*.md; do
    [[ -f "$f" ]] || continue
    emit_file "~/.claude/skills/worklog/modes/$(basename "$f")" "$f"
  done
  for f in "$HOME"/.claude/skills/worklog/references/*.md; do
    [[ -f "$f" ]] || continue
    emit_file "~/.claude/skills/worklog/references/$(basename "$f")" "$f"
  done
  emit_file "~/.codex/skills/worklog/SKILL.md"  "$CODEX_SKILL_SRC"
  for f in "$HOME"/.codex/skills/worklog/modes/*.md; do
    [[ -f "$f" ]] || continue
    emit_file "~/.codex/skills/worklog/modes/$(basename "$f")" "$f"
  done
  for f in "$HOME"/.codex/skills/worklog/references/*.md; do
    [[ -f "$f" ]] || continue
    emit_file "~/.codex/skills/worklog/references/$(basename "$f")" "$f"
  done

  printf '\n## Section 3 — agent settings/config (advisory, do not clobber)\n'
  emit_file "~/.claude/settings.json"        "$SETTINGS"
  emit_file "~/.claude/settings.local.json"  "$SETTINGS_LOCAL"
  emit_file "~/.codex/config.toml"           "$CODEX_CONFIG"

  printf '\n## Section 4 — Memory templates (DRAFT — skill distills to skeleton)\n'
  if [[ -d "$MEM_DIR" ]] && ls "$MEM_DIR"/*.md >/dev/null 2>&1; then
    for f in "$MEM_DIR"/*.md; do
      emit_file "memory/$(basename "$f")" "$f"
    done
  else
    printf '\n_(no memory files to template — memory dir is empty on source machine)_\n'
  fi

  cat <<'CHECKLIST'

---

## Post-setup checklist

- [ ] `gh repo view <your-org>/_worklog` succeeds
- [ ] `cd ~/Documents/projects/_worklog && ls people/` shows your `<ldap>/` dir with `active/` and `archive/`
- [ ] `bin/install-hooks.sh --write` exits 0 and `~/.claude/settings.json` contains a PreCompact hook pointing at `bin/autosave.sh`
- [ ] `~/.claude/skills/worklog/SKILL.md` exists; `/worklog help` in a fresh Claude session prints the menu
- [ ] `~/.codex/skills/worklog/SKILL.md` exists; `worklog help` in a fresh Codex session prints the menu after restart if needed
- [ ] `/worklog init` completes without errors and reports 0 active tasks
- [ ] `rg --version` succeeds (tier-1 retrieval — required for interactive grep over tasks; bin scripts fall back to POSIX grep)
- [ ] serena MCP configured — enables tier-2 structure-aware semantic search over markdown. Works across Claude Code, Codex CLI/App, Cursor, Gemini-CLI, JetBrains, VSCode assistants (any MCP-capable client). Fall back to `rg` heading anchors if MCP unavailable.
- [ ] (Optional, only if concept-search repeatedly misses) tier-3 hybrid index: design in `docs/rag-format.md § Retrieval tiers`. Do not build speculatively.
- [ ] (Optional) `/worklog sync my-first-task` creates a task file end-to-end

If any step fails, stop and ask the user — do not paper over.
CHECKLIST
} >"$DRAFT"

# ---- post-scrub verification -------------------------------------------------
# Double-check the assembled draft: no lingering org strings, no unmasked
# secrets. This is belt-and-braces; individual scrub() runs should've caught
# everything, but assembly could introduce new text (headers, preamble).
check_residue() {
  local file="$1" pattern="$2" label="$3"
  local hits
  hits="$(grep -cE "$pattern" "$file" 2>/dev/null || true)"
  if [[ "$hits" -gt 0 ]]; then
    echo "WARN: $hits $label residue hit(s) in draft" >&2
  fi
}
check_residue "$DRAFT" "[Ii]deogram|@ideogram\\.ai"                                     "org-identifier"
check_residue "$DRAFT" "(^|[^A-Za-z0-9_])${LDAP}([^A-Za-z0-9_]|$)"                       "ldap"
check_residue "$DRAFT" "sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{35}|AKIA[0-9A-Z]{16}|github_pat_[A-Za-z0-9_]{20,}|xox[abpros]-[A-Za-z0-9-]{10,}" "secret"

SIZE=$(wc -c <"$DRAFT" | tr -d ' ')
FILES=$(grep -c '^=====WORKLOG-EXPORT-FILE=====' "$DRAFT" || true)

if (( DRY_RUN )); then
  echo "dry-run:"
  echo "  ldap:   $LDAP"
  echo "  files:  $FILES"
  echo "  bytes:  $SIZE"
  echo "  would write: $OUT"
  exit 0
fi

cp "$DRAFT" "$OUT"
echo "wrote $OUT ($FILES files, $SIZE bytes)"
