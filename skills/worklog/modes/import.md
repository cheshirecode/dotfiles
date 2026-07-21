# Mode: `import`

Read a worklog export artifact (produced by `/worklog export` on
another machine) and merge it into this machine's setup. LLM-judged
per-file — no bash scripts, no new tool dependencies. Subsumes the
bootstrap case (no prior worklog setup → every file is "new, write").

**Does not run the preamble.** No `_worklog` pull. Operates on local
files directly.

**Env prerequisite (no-preamble mode):** know `WORKLOG_BIN` / `WORKLOG_REPO` paths before merging skill or docs files so post-import helpers resolve.

## Input format

Artifact files are sentinel-delimited multipart (not markdown fences,
which would collide with embedded ``` in exported markdown). Each file
block looks like:

    =====WORKLOG-EXPORT-FILE=====
    PATH: <target-path>
    =====WORKLOG-EXPORT-CONTENT=====
    <raw content — may contain anything, including ``` fences>
    =====WORKLOG-EXPORT-END=====

Parse with awk. Enumerate all `PATH:` values first:

```
awk '/^=====WORKLOG-EXPORT-FILE=====/{f=1;next}
     f && /^PATH: /{print substr($0,7); f=0}' <artifact>
```

Extract a single file's content:

```
awk -v p="<target>" '
  /^=====WORKLOG-EXPORT-FILE=====/{f=0;next}
  /^PATH: /{if (substr($0,7)==p) f=1; next}
  /^=====WORKLOG-EXPORT-CONTENT=====/{if (f) c=1; next}
  /^=====WORKLOG-EXPORT-END=====/{c=0}
  c' <artifact>
```

## Steps

1. **Validate.** Artifact must have ≥1 matching file sentinel pair. If
   not, refuse: "not a worklog export artifact".

2. **Resolve this machine's placeholder values.**
   - `cheshirecode` → `bin/_lib.sh::resolve_ldap`.
   - `cheshirecode` → `gh repo view --json owner -q .owner.login` on
     `_worklog` if cloned, else prompt.
   - `users.noreply.github.com` → from `git config user.email`, else prompt.
   - `cheshirecode/<repo>` → prompt (list B's actual primary repo(s)).
   Substitute in-memory before any write. Leftover `<your-*>` in
   content → flag for manual review, don't write.

3. **Per-file judgment** (read both sides, decide):

   | Target state | Action |
   |---|---|
   | Missing on B | **Write** A's version |
   | Byte-identical | **No-op** |
   | Markdown (`.md`) diverges | **Merge**: combine additively — new sections from A added to B, preserved customizations from B kept. Applies to `AGENTS.md`, `README.md`, `docs/*.md`, the skill `SKILL.md`, **and all `modes/*.md` and `references/*.md` files under `~/.claude/skills/worklog/` and `~/.codex/skills/worklog/`**. When reconciling conflicting wording, prefer A's (artifact is the "latest" being imported) unless B's customization is clearly intentional (renamed helper, custom hook path, agent-specific local behavior). Uncertain → skip + flag. |
   | Script (`bin/*.sh`, `*.py`) diverges | **Accept or skip only.** No semantic merge on code. Pick the side that looks newer / more complete; when truly divergent customizations exist on both sides, skip + flag. |
   | Other text files (`.gitignore`, `.editorconfig`, etc.) diverges | **Accept or skip only.** No semantic merge on rule/config files — merging line-by-line loses order-sensitive semantics or breaks dedup. Pick the side that looks authoritative; skip + flag if uncertain. |
   | Path under `people/` | **Never write.** Shouldn't be in artifact anyway — refuse the whole import if present. |

4. **Write.** For each accept/merge decision, write the substituted
   content to the real target. For any file under `bin/` ending in
   `.sh` or `.py`, `chmod +x` after write.

5. **Advisory-only sections.**
   - `~/.claude/settings.json` / `settings.local.json`: do NOT write.
     Show the artifact's version and diff vs. B's current in the
     summary so the user can hand-merge.
   - `~/.codex/config.toml`: do NOT write. It is durable config, but it
     is still machine-local because it contains trusted project paths,
     plugin enablement, and MCP wiring. Show it as advisory diff only.
   - `memory/*.md` (skeleton templates): show the templates so the
     user can seed or update their memory dir manually.

6. **Report.** One block summary:

   ```
   import:
     written     N  (auto-applied)
     merged      M  (markdown combined)
     skipped     K  (B's version kept)
     flagged     F  (divergent scripts / unresolved placeholders — manual)
     advisory    A  (settings/memory — not written)
   ```

   Followed by flagged-file paths and advisory diffs.

7. **Suggest a checkpoint:** `"$WORKLOG_BIN/checkpoint.sh" worklog-import-<date>`
   so the `_worklog` edits land in git. The worklog repo tracks
   protocol/skill changes under `people/cheshirecode/` the same way any
   other task would.

## Boundaries

- **Never** write under `people/`. Refuse if artifact contains one.
- **Never** write to `~/.claude/settings*.json`, `~/.codex/config.toml`,
  or memory files.
- **Never** delete a file present on B but absent on A — artifact is
  not authoritative for deletion.
- Placeholder substitution happens before write; any leftover
  `<your-*>` marks that file as flagged, not written.
- Skill reads the artifact directly (`Read` tool); no `bin/import-*`
  script is needed. Parsing is awk one-liners.

## Round-trip sanity check

If A and B are already in sync (same protocol versions), `/worklog
import` on B should produce zero writes, zero merges — everything
byte-identical. Use that as the smoke test.
