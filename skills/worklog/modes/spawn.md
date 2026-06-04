# Mode: `spawn`

Emit a self-contained handoff prompt for a fresh Claude Code session. The spawned session assumes **no memory** of the current conversation — the prompt must stand alone.

**Does not run the preamble.** No LDAP resolution, no `_worklog` pull, no repo writes. Pure prompt generator.

## Steps

1. Parse the free-form task from the argument verbatim. Everything after `spawn` is the task description.
2. Resolve `$PROJECTS_DIR` using the same rules as the preamble: `dirname "$(git rev-parse --show-toplevel)"` → first existing of `~/Documents/projects` `~/projects` `~/code` `~/src` `~/dev` `~/repos` → ask. Do not clone or pull.
3. Infer which repos and skill files the task touches (keyword match on the description — e.g. `cheshirecode/<repo>` / `cheshirecode/<repo>` / `cheshirecode/<repo>`, or skill names from `.claude/skills/`). Include only what's relevant; don't dump everything.
4. Render the handoff prompt inside a fenced code block. Do **not** execute it.

## Prompt template

```
You're picking up a task cold. Assume no prior session memory.

Project root: <$PROJECTS_DIR>
Relevant repos:
  - <$PROJECTS_DIR>/<repo-a>
  - <$PROJECTS_DIR>/<repo-b>

Read these first (in order):
  - <$PROJECTS_DIR>/_worklog/AGENTS.md          # worklog protocol
  - <$PROJECTS_DIR>/<repo>/AGENTS.md            # repo conventions (if the task touches code)
  - <path to any skill SKILL.md that governs the work>
  - <path to the active worklog task file, if one exists>

Task:
  <verbatim task description from the user>

Deliverables:
  <one-line expectation — PR, file, prompt, report, etc.>
  End with a checkpoint: `cd <$PROJECTS_DIR>/_worklog && bin/checkpoint.sh <slug>`
  (or create a task file first via `/worklog sync` if none exists).
```

Tune the "Read these first" list to the task. Examples:
- Task touches `_worklog` protocol → include `_worklog/AGENTS.md` + `_worklog/docs/protocol.md`.
- Task edits a skill → include that skill's `SKILL.md`.
- Task is a code change in a known repo → include that repo's root `AGENTS.md` and the nearest nested `AGENTS.md`.
- Task is pure research / survey → worklog `AGENTS.md` only.

Keep the prompt under ~30 lines. If the task is genuinely large, point at a single design doc in the prompt rather than inlining its content.
