# Compaction preservation kernel — worklog-aware

Agent-neutral preservation prompt. Use whenever an LLM session is about to summarize itself (Claude Code's `/compact`, Codex CLI's auto-compaction, a Cursor session handoff, or a human asking the model to "summarize the context"). The block below the divider is the actual preservation kernel — keep it terse; a long preservation prompt defeats the point of compacting.

Invocations:

- **Claude Code:** `/compact $(cat docs/compact-instruction.md)`
- **Codex CLI / Cursor / manual summarization:** paste the block below verbatim as the summarizer's instruction, or run `bin/compact-kernels.sh` first so `.cache/compact-kernels.md` is fresh for the next session to consume.

---

Preserve (anchor the summary around these; the task file is the source of truth, not your summary):

- Active task slug(s) currently in play and their frontmatter `status:` + `next_action:` verbatim.
- The last pushed SHA on `main` in `_worklog` and any in-flight PR numbers in the target code repo.
- Any mid-debug state: open error message, hypothesis in flight, what has already been ruled out.
- Active invariants and constraints that are not obvious from re-reading the task file (e.g. "must stay on Node 16", "can't touch the public API surface").
- Files currently scoped in / out of the change.

Drop aggressively:

- File-read outputs, directory listings, tool-call transcripts that are no longer load-bearing.
- Resolved errors, dead debugging tangents, superseded reasoning or draft code.
- Anything already captured in `people/<ldap>/active/<slug>.md` — reference the file path instead of re-embedding.

After compacting, state the current slug + `next_action:` back to the user as a verification check, then re-read `people/<ldap>/active/<slug>.md` before your first action. If the summary and the file disagree, the file wins.

If `_worklog/.cache/compact-kernels.md` exists (auto-dumped by the `PreCompact` hook), read it once on resume — one 7-line kernel per active task. That gives you all-active-tasks orientation for the price of one file, before you open any specific task file. The task file remains authoritative; the kernel is a signpost.
