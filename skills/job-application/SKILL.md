---
name: job-application
description: Generate a tailored job-application package (resume + cover letter + skills keyword block) for one JD. Use when the user names a job URL or job ID and wants an application produced — e.g. "apply to <url>", "generate a resume for <gh_jid>", "tailor for the staff engineer role at X". Triggers any "produce an application", "tailor for this JD", "I need a resume that targets Y" request. Scope boundary — one named JD in, one application package out; not general resume review, not interview prep, not career strategy.
---

# job-application

Pattern for producing one tailored application package from worklog evidence + a target JD. Codified from the 2026-08-27 Elastic gh_jid 8106089 run; lessons at `people/oss/active/job-application-elastic-8106089.md`.

## When to use

- User names a job URL or Greenhouse/Lever/Workday ID and wants an application produced.
- The user has a canonical career-evidence repo (`_worklog` or equivalent) the skill can search for real PR numbers, dates, and metrics.
- Output is one or more `.txt` files (or `.docx` if the user asks) saved locally; **the user uploads manually** (the Drive MCP is read-only for folder/file creation in this environment).

Skip / downgrade if: trivial blanket application, no worklog evidence to anchor claims, or the user just wants a generic CV refresh with no target JD (out of scope — this skill tailors against a specific JD).

## Pipeline (do not reorder)

### 1. JD-pull

Fetch the full JD. Record the **required** vs **bonus** split. If the JD is on Greenhouse, the og:description tag in the HTML usually contains the entire JD as one string — extract it directly. Note: salary, location, and visa language.

### 2. Fit-assessment

Map each JD requirement (required + bonus) to worklog evidence. For each row: `Strong` / `Gap (honest)` / `Gap (stretch)`. Honest gaps are acceptable to surface; stretch gaps require the candidate to either learn or skip.

If most required rows are `Gap (stretch)`, stop and surface that to the user before drafting. Don't burn cycles producing a low-signal application.

### 3. Pick the angle

Choose 2–3 strongest evidence clusters. Lead with those in resume + cover letter. Never claim gaps as strengths. Stretch roles go honest-stretch: name the gap explicitly in the cover letter (`Where I am growing`) rather than papering over with synonyms a human will see through in 10 seconds.

### 4. Produce three artifacts

Save locally — never pretend to upload to Drive.

**Output root (default):** `./applications/<company>-<jobid>/`, relative to the
directory the session was started in. `<company>` is a lowercase slug
(`elastic`), `<jobid>` is the ID from the JD URL (`8106089`). Create it if
absent (`mkdir -p`). Use a different root only if the user names one, and then
use that root everywhere below. Every path in Step 5 and in the Output
checklist refers to this same folder.

1. **Resume** (`.txt` by default; `.docx` if the user asked). One page. Lead with the angle. Cite only PR numbers findable in worklog (`grep -r <pr> <worklog>` before writing).
2. **Cover letter** (`.txt` by default). 90-second human read. Three concrete shipped patterns in priority order, each anchored to evidence. Honest gap carve-out if stretch.
3. **Skills keyword block** (`.txt` by default). 30+ keywords covering required + bonus. Use the candidate's actual evidence vocabulary, not invented synonyms. This is for the AI-screening free-text field; the resume prose is for humans.

Naming convention, inside the output root: `resume-<company>-<jobid>.txt`, `cover-letter-<company>-<jobid>.txt`, `skills-keywords-<company>-<jobid>.txt`. `UPLOAD-INSTRUCTIONS.txt` (Step 5) goes in the same folder.

### 5. Hand off for upload

Always write the three artifacts into `./applications/<company>-<jobid>/`
first (Steps 4.1–4.3). Then write `UPLOAD-INSTRUCTIONS.txt` into that same
folder, with **two parallel paths** depending on whether `gws` is available:

**Path A — manual (always works).** Drag-and-drop the three files into a
per-application Drive folder. Suggested folder name:
`<Company> — <jobid> — <YYYY-MM-DD>` (e.g. `Elastic — 8106089 — 2026-08-27`).
The date is the application date, not the JD post date — re-runs on the
same job create a new dated folder, preserving the audit trail.

**Path B — gws one-liner (when `gws --version` succeeds AND `gws auth setup`
has been completed).** The instructions file contains a copy-pasteable
shell snippet the user can run to create the folder and upload the three
artifacts in one go. The snippet is built once, after artifacts are saved,
so file paths are real:

Substitute the four variables at the top when writing the file — everything
below them is literal, and the snippet must run as-is once they are filled in.

```bash
# Filled in by the skill when UPLOAD-INSTRUCTIONS.txt is written.
COMPANY="Elastic"     # display name, used in the Drive folder title
CO="elastic"          # lowercase slug, must match the local filenames
JID="8106089"         # job ID from the JD URL
DATE="2026-08-27"     # application date, not the JD post date
OUT="./applications/${CO}-${JID}"

# Create the per-application folder (idempotent: search first, create if absent).
FOLDER_NAME="${COMPANY} — ${JID} — ${DATE}"
EXISTING=$(gws drive files list \
  --params "{\"q\": \"name = '${FOLDER_NAME}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false\"}" \
  --format json | jq -r '.files[0].id // empty')
FOLDER_ID="${EXISTING:-$(gws drive files create \
  --json "{\"name\": \"${FOLDER_NAME}\", \"mimeType\": \"application/vnd.google-apps.folder\"}" \
  --format json | jq -r '.id')}"

# Upload the three artifacts into that folder.
for f in "resume-${CO}-${JID}.txt" "cover-letter-${CO}-${JID}.txt" "skills-keywords-${CO}-${JID}.txt"; do
  gws drive files create \
    --upload "${OUT}/${f}" \
    --json "{\"name\": \"${f}\", \"parents\": [\"${FOLDER_ID}\"]}"
done
```

If `gws` is missing, Path B is omitted from `UPLOAD-INSTRUCTIONS.txt`.
The skill **never writes to Drive on its own** — both paths require the
user to act. Privacy + auditability are preserved; speed is opt-in.

The historical note that "the gdrive MCP is read-only" still holds; `gws`
is the supported write path. Both paths in `UPLOAD-INSTRUCTIONS.txt` are
still manual-from-the-agent's-perspective.

## Lessons (apply by default)

- **L1 — Anchor every claim to worklog.** Grep before citing. PR numbers, dates, metrics — all must be findable in the canonical evidence repo.
- **L2 — Skills-keyword block is separate from resume prose.** Different readers, different artifacts.
- **L3 — Honest-stretch beats keyword-max.** Stretch roles surface gaps in the cover letter; do not over-claim.
- **L4 — Drive upload is manual.** Produce local files + handoff instructions; do not fake it.
- **L5 — Stop early on low fit.** If most required rows are gap, tell the user before drafting.
- **L6 — Drive linkage (read Drive → local → worklog fallback; write never silent).**
  - **Read flow:** try `gws drive files get` on the canonical resume first (the
    Drive file ID is recorded in the worklog task file, not in the skill);
    fall back to `$HOME/<canonical-resume>` if Drive returns 401/403/404;
    fall back to worklog evidence directly if no file exists.
  - **Write flow:** never silent. The skill produces local files; the
    `UPLOAD-INSTRUCTIONS.txt` always contains the manual drag-and-drop
    path, and **only when `gws --version` succeeds AND `gws auth setup`
    is complete**, also the one-liner shell snippet for folder create +
    upload. User pastes; agent doesn't run.
  - **Folder convention:** `<Company> — <jobid> — <YYYY-MM-DD>` (date =
    application date). Idempotent: search by name first, create only if absent.
  - **Worklog is still the source of truth for fit-assessment.** Drive is
    a deliverable surface. Anything copied to Drive is a *pointer* to the
    worklog task, not a duplicate of its evidence.

## Output checklist

Before declaring done, verify:
- [ ] All PR numbers cited are findable in worklog via grep
- [ ] Cover letter has the honest-stretch carve-out (or is omitted for non-stretch roles)
- [ ] Skills keyword block covers required + bonus terminology
- [ ] All four files are saved under `./applications/<company>-<jobid>/` (or the root the user named) with the Step 4 naming convention
- [ ] `UPLOAD-INSTRUCTIONS.txt` is written with **both** Path A (manual) and — when `gws --version` succeeds AND auth is complete — Path B (gws one-liner)
- [ ] Per-application Drive folder name in the instructions matches `<Company> — <jobid> — <YYYY-MM-DD>`
- [ ] If the canonical resume was read from Drive, the worklog task file records the file ID (for re-runs and re-uploads)
- [ ] A worklog task is created recording the run (per `worklog` skill): JD text, fit-assessment matrix, angle, file manifest

## Worked example

`people/oss/active/job-application-elastic-8106089.md` in the worklog.
Reference it for the full JD, 15-row fit-assessment matrix, and the six
codified lessons that this skill distills down. For the Drive-linkage
design that produced L6 and Path B in Step 5, see
`gws-skill-drive-linkage-design` in the worklog archive (includes the
live Drive-state table of canonical file IDs, sizes, and modification
times that the read flow should target).
