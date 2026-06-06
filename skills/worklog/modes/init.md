# Mode: `init`

Onboard a session. Light by default; escalates to a full external scan when drift is detected or the user explicitly asks.

## Detection — light vs. full

Run these checks after the preamble:

```bash
ACTIVE_COUNT=$(ls people/$LDAP/active/*.md 2>/dev/null | wc -l | tr -d ' ')
LAST_COMMIT_DAYS=$(git log -1 --format=%ct --author="$LDAP@" -- people/$LDAP/ 2>/dev/null \
  | awk -v now=$(date +%s) '{print int((now-$1)/86400)}')
```

| Condition                                          | Default action                                           |
| -------------------------------------------------- | -------------------------------------------------------- |
| `people/$LDAP/` missing                            | Bootstrap (preamble step 4), then run **full** scan.     |
| `$ACTIVE_COUNT` = 0                                | Run **light** survey. Offer `--full` if user wants more. |
| `$ACTIVE_COUNT` ≥ 1 AND `$LAST_COMMIT_DAYS` < 7    | **Light** (read `active/`, verify against `gh pr list`). |
| `$ACTIVE_COUNT` ≥ 1 AND `$LAST_COMMIT_DAYS` ≥ 7    | Run **light**; point at `--full` if drift is detected.   |

**Explicit overrides:** `/worklog init --full` always runs the full scan; `/worklog init --light` always skips it.

**Drift signals** (trigger the "point at `--full`" suggestion during a light run):
- Open PR on GitHub (`gh pr list --author @me --state open`) whose number/URL doesn't appear in any active task file.
- Active task with `status: in-review` whose PR is merged or closed on GitHub.
- Active task with `status: shipping` whose `last_updated` is >14 days old.

## Light path

Read-only sync, no writes.

1. `ls people/$LDAP/active/` — print slugs.
2. For each known repo under `$PROJECTS_DIR` (`cheshirecode/<repo>`, `cheshirecode/<repo>`, `cheshirecode/<repo>`, `cheshirecode/<repo>`, `_worklog`), run `gh pr list --author @me --state open --json number,title,url,headRepository --limit 20` in parallel and cross-reference against active task files.
3. Report drift lines if any. Do not write.

Output:

```
LDAP: cheshirecode
worklog: synced at <short-sha>
active tasks (N):
  - <slug-a>.md
  - <slug-b>.md
drift:
  - <repo>#<pr>  not tracked in any active task  (run `/worklog init --full` to propose)
  - <slug>       PR #<n> merged on GitHub but status=in-review
ready — which task?
```

## Tracker hydration (MUST, on every init)

After printing the active-task list and before asking "which task?", **hydrate the in-session tracker** for any active task with ≥3 unchecked items in its `## Next` section. Per AGENTS.md § In-session progress visibility:

- **Claude Code:** invoke `TaskCreate` for each unchecked `- [ ]` item under `## Next`. Use the slug as the task's `metadata.slug` so the tracker entry maps back to its source task file.
- **OpenAI Codex CLI:** emit an initial `update_plan` populated from the same `## Next` items.
- **Cursor:** populate the canvas todo card / Plan Mode entries.

Run `"$WORKLOG_BIN/context.sh" <slug>` for any focused task — its output's "Tracker-ready snippet" section formats each unchecked item ready to paste/exec.

Skip hydration only when every active task is at ≤2 unchecked items (single-step or trivial). Don't wait for the user to ask. Drift evidence: 2026-04-27 review session ran ~30 multi-step commits with zero `TaskCreate` invocations despite the system reminder firing repeatedly (`docs/lessons.md` 2026-04 entry).

## Full path

Expensive: scans GitHub + Linear + Notion + Slack. Warn first:

> `/worklog init --full` queries GitHub, Linear, Notion, and Slack (last 90 days); it takes a few minutes. Proceed?

Wait for acknowledgement.

1. **Verify auth in parallel.** Stop with a clear message if any fails:
   - `gh auth status`
   - Linear MCP: `mcp__claude_ai_Linear__get_user` (self)
   - Notion MCP: `mcp__claude_ai_Notion__notion-get-users`
   - Slack MCP: `mcp__claude_ai_Slack__slack_search_users` for the user's own LDAP/name (degrade gracefully — if Slack auth is missing, skip step 2's Slack pull and note it in the report; don't hard-fail the whole init).

2. **Pull external state in parallel.**
   - **GitHub:** `gh pr list --author @me --state open --json number,title,url,headRepository,isDraft,reviewDecision` across known repos; `gh issue list --assignee @me --state open`.
   - **Linear:** `mcp__claude_ai_Linear__list_issues` filtered to assignee=self, non-terminal states.
   - **Notion:** `mcp__claude_ai_Notion__notion-search` for pages owned/recently-edited by user; filter to design/RFC-shaped docs (skip meeting notes).
   - **Slack:** `mcp__claude_ai_Slack__slack_search_public_and_private` with query `from:@me after:<90d-ago-YYYY-MM-DD>`. Compute the date once: `date -v-90d +%Y-%m-%d` (macOS) or `date -d '90 days ago' +%Y-%m-%d` (linux). Cap at ~50 most-recent matches; we want signal, not exhaustive history. The goal is to surface ongoing support/discussion threads that may warrant a task — Sarah Vo's use case (worklog-codex-compat thread, 2026-04-29) was support work happening in Slack that never materialized as a task file.

3. **Match against existing task files.** Load `people/$LDAP/active/*.md` and recent `archive/*.md`. Match by:
   - `linear:` frontmatter vs Linear issue key.
   - `pr:` frontmatter or PR numbers cited in body vs GitHub PR number.
   - `notion:` frontmatter vs Notion page ID.
   - **Slack:** match by `external_refs:` entries with `platform: slack` (canonical: `url:` is the message permalink — channel+ts encodes the thread), or by mentions of PR numbers / Linear IDs inside the Slack message text. Slack threads rarely have a flat frontmatter key — most matches will be implicit via cross-referenced IDs. A Slack thread that mentions no tracked external ID and has no `external_refs:` hit is a `[propose]` candidate.

4. **Report, grouped, no writes yet.**

   ```
   [tracked]  <external-id>  <slug>           — already mapped
   [propose]  <external-id>  (new)            — <one-line title>, suggested slug: <slug>
   [stale]    <external-id>  <slug>           — external item is closed/merged; consider archive
   ```

   Counts at the bottom: `N tracked · M propose · K stale`.

5. **Wait** for the user to pick which `[propose]` items to materialize and which `[stale]` items to archive.

6. **Write, per user direction.** Use the writing rules from `sync` (below). Batch commits by slug, single push at the end.

**Boundaries:**
- Never touch peers' task files regardless of what external systems surface.
- If an external item has no clear ownership, list it under `[propose]` with a `TODO:` marker and let the user decide.
- Notion results are noisy — skip obvious non-work pages rather than proposing a task for each.
- Slack results are noisier than Notion. Skip casual chat, social, and one-off questions; only propose threads that look like sustained work (multi-message thread, you are the helper, references code/PR/Linear, or spans multiple days). When in doubt, surface as a one-line "Slack signal" note rather than a `[propose]` task.
