---
name: job-application
description: Generate a tailored job-application package (resume + cover letter + skills keyword block) for one JD. Use when the user names a job URL or job ID and wants an application produced — e.g. "apply to <url>", "generate a resume for <gh_jid>", "tailor for the staff engineer role at X". Triggers any "produce an application", "tailor for this JD", "I need a resume that targets Y" request. Not for general resume reviews or interview prep (those live in `career-interview-matrix` / `worklog`).
---

# job-application

Pattern for producing one tailored application package from worklog evidence + a target JD. Codified from the 2026-08-27 Elastic gh_jid 8106089 run; lessons at `people/oss/active/job-application-elastic-8106089.md`.

## When to use

- User names a job URL or Greenhouse/Lever/Workday ID and wants an application produced.
- The user has a canonical career-evidence repo (`_worklog` or equivalent) the skill can search for real PR numbers, dates, and metrics.
- Output is one or more `.txt` files (or `.docx` if the user asks) saved locally; **the user uploads manually** (the Drive MCP is read-only for folder/file creation in this environment).

Skip / downgrade if: trivial blanket application, no worklog evidence to anchor claims, or the user just wants a generic CV refresh (that's `career-interview-matrix`).

## Pipeline (do not reorder)

### 1. JD-pull

Fetch the full JD. Record the **required** vs **bonus** split. If the JD is on Greenhouse, the og:description tag in the HTML usually contains the entire JD as one string — extract it directly. Note: salary, location, and visa language.

### 2. Fit-assessment

Map each JD requirement (required + bonus) to worklog evidence. For each row: `Strong` / `Gap (honest)` / `Gap (stretch)`. Honest gaps are acceptable to surface; stretch gaps require the candidate to either learn or skip.

If most required rows are `Gap (stretch)`, stop and surface that to the user before drafting. Don't burn cycles producing a low-signal application.

### 3. Pick the angle

Choose 2–3 strongest evidence clusters. Lead with those in resume + cover letter. Never claim gaps as strengths. Stretch roles go honest-stretch: name the gap explicitly in the cover letter (`Where I am growing`) rather than papering over with synonyms a human will see through in 10 seconds.

### 4. Produce three artifacts

Save locally — never pretend to upload to Drive:

1. **Resume** (`.txt` by default; `.docx` if the user asked). One page. Lead with the angle. Cite only PR numbers findable in worklog (`grep -r <pr> <worklog>` before writing).
2. **Cover letter** (`.txt` by default). 90-second human read. Three concrete shipped patterns in priority order, each anchored to evidence. Honest gap carve-out if stretch.
3. **Skills keyword block** (`.txt` by default). 30+ keywords covering required + bonus. Use the candidate's actual evidence vocabulary, not invented synonyms. This is for the AI-screening free-text field; the resume prose is for humans.

Naming convention: `resume-<company>-<jobid>.txt`, `cover-letter-<company>-<jobid>.txt`, `skills-keywords-<company>-<jobid>.txt`. Co-locate in a folder per application.

### 5. Hand off for manual upload

Write a short `UPLOAD-INSTRUCTIONS.txt` next to the artifacts:
- Suggested Drive folder name (e.g. `<Company> — <gh_jid> — <title>`).
- Step-by-step upload + form-submit checklist.
- Note that the `gdrive` MCP in this environment is read-only (`list_mcp_resources` shows no `gdrive_create_folder` or `gdrive_upload_file`).

## Lessons (apply by default)

- **L1 — Anchor every claim to worklog.** Grep before citing. PR numbers, dates, metrics — all must be findable in the canonical evidence repo.
- **L2 — Skills-keyword block is separate from resume prose.** Different readers, different artifacts.
- **L3 — Honest-stretch beats keyword-max.** Stretch roles surface gaps in the cover letter; do not over-claim.
- **L4 — Drive upload is manual.** Produce local files + handoff instructions; do not fake it.
- **L5 — Stop early on low fit.** If most required rows are gap, tell the user before drafting.

## Output checklist

Before declaring done, verify:
- [ ] All PR numbers cited are findable in worklog via grep
- [ ] Cover letter has the honest-stretch carve-out (or is omitted for non-stretch roles)
- [ ] Skills keyword block covers required + bonus terminology
- [ ] Files are saved locally with consistent naming
- [ ] `UPLOAD-INSTRUCTIONS.txt` is written
- [ ] A worklog task is created recording the run (per `worklog` skill): JD text, fit-assessment matrix, angle, file manifest

## Worked example

`people/oss/active/job-application-elastic-8106089.md` in the worklog.
Reference it for the full JD, 15-row fit-assessment matrix, and the six
codified lessons that this skill distills down.
