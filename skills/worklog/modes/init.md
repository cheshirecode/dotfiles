# Mode: `init`

**Routing contract:** Default and `--light` use `preamble.sh --minimal`; only
explicit `--full` uses `preamble.sh --full`. Select the preamble from the user
flag before reading this mode. Light init must not pull, autosave, commit, push,
or rebuild caches.

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
2. Discover the repos to scan: `ls -d "$PROJECTS_DIR"/*/` (each clone is a candidate; `_worklog` is always included). Keep the ones that are git clones with a GitHub remote — `git -C <dir> remote get-url origin`. If `$PROJECTS_DIR` holds no clones, prompt the user for the repo list rather than guessing. For each, run `gh pr list --author @me --state open --json number,title,url,headRepository --limit 20` in parallel and cross-reference against active task files.
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

## Tracker hydration (after focus selection)

The active-task list is orientation, not an instruction to materialize every
durable task in an ephemeral tracker.

Do not hydrate `TaskCreate` or `update_plan` before the user selects a task.

After the user selects or resumes a slug, run
`"$WORKLOG_BIN/context.sh" <slug>`. Its "Tracker-ready snippet" formats that
task's unchecked `## Next` items. Hydrate only that focused task:

- **Claude Code:** invoke `TaskCreate` for its unchecked items, using the slug
  as `metadata.slug`.
- **OpenAI Codex CLI:** emit `update_plan` for the same focused items.
- **Cursor:** populate the focused canvas todo card / Plan Mode entries.

Skip hydration when the selected task has at most two unchecked items. The
durable task files remain the multi-task backlog; the tracker mirrors only the
work this session intends to execute.

## Full path

Expensive: scans GitHub + Linear + Notion + Slack. Warn first:

> `/worklog init --full` queries GitHub, Linear, Notion, and Slack (last 90 days); it takes a few minutes. Proceed?

Wait for acknowledgement.

1. **Verify auth in parallel.** Only `gh auth status` is required — stop with a clear message if it fails. Linear, Notion, and Slack are OPTIONAL enrichment sources: degrade gracefully — if one's auth is missing, skip its step-2 pull and note the gap in the report; don't hard-fail the whole init.
   - `gh auth status` — **required**
   - Linear MCP: `mcp__claude_ai_Linear__get_user` (self) — optional
   - Notion MCP: `mcp__claude_ai_Notion__notion-get-users` — optional
   - Slack MCP: `mcp__claude_ai_Slack__slack_search_users` for the user's own LDAP/name — optional

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
