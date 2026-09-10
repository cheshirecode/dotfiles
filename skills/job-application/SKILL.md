---
name: job-application
description: Generate a tailored job-application package (resume, cover letter, and skills keyword block) for one job description. Use when the user provides a job URL or ID and asks to apply, generate a resume, or tailor application materials. Scope is one named job description and one application package; exclude general resume review, interview prep, and career strategy.
---

# job-application

Produce one tailored application package from career evidence and a target job description.

## When to use

- User names a job URL or Greenhouse/Lever/Workday ID and wants an application produced.
- The user has a canonical career-evidence repo (`_worklog` or equivalent) the skill can search for real PR numbers, dates, and metrics.
- Output is one or more `.txt` files (or `.docx` if the user asks) saved locally; **the user uploads manually**.

Skip / downgrade if: trivial blanket application, no worklog evidence to anchor claims, or the user just wants a generic CV refresh with no target JD (out of scope — this skill tailors against a specific JD).

## Canonical resume evidence

If the task records a canonical Drive file ID, try the available Drive reader
or `gws drive files get`. If Drive is unavailable or no file ID is recorded,
try the user’s canonical local resume; fall back to worklog evidence only if
that local source is also unavailable. Verify each claim
against the evidence repository. Resolve capabilities in the current environment
rather than assuming a connector is always read-only. Record a Drive file ID
in the task when used so later runs can find the same source.

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

1. **Resume** (`.txt` by default; `.docx` if the user asked). One page. Lead with the angle. Cite only PR numbers findable in worklog (`rg <pr> <worklog>` before writing).
2. **Cover letter** (`.txt` by default). 90-second human read. Three concrete shipped patterns in priority order, each anchored to evidence. Honest gap carve-out if stretch.
3. **Skills keyword block** (`.txt` by default). 30+ keywords covering required + bonus. Use the candidate's actual evidence vocabulary, not invented synonyms. This is for the AI-screening free-text field; the resume prose is for humans.

Naming convention, inside the output root: `resume-<company>-<jobid>.txt`, `cover-letter-<company>-<jobid>.txt`, `skills-keywords-<company>-<jobid>.txt`. `UPLOAD-INSTRUCTIONS.txt` (Step 5) goes in the same folder.

### 5. Hand off for upload

Write `UPLOAD-INSTRUCTIONS.txt` beside the actual saved artifacts. It always
includes manual drag-and-drop into a folder named
`<Company> — <jobid> — <YYYY-MM-DD>` (application date).

Only when `gws --version` succeeds and existing auth is configured, read
[references/upload.md](references/upload.md) and include its filled-in script.
Use the actual output root and filenames from Step 4, including `.docx` when
requested. The user runs the script; do not execute uploads as part of drafting.

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
