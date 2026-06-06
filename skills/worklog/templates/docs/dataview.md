# Dataview snippet library

Drop-in queries for the Dataview Obsidian plugin. Open this vault in Obsidian with [Dataview](https://github.com/blacksmithgu/obsidian-dataview) installed and these blocks render as live tables/lists. In non-Obsidian readers (GitHub, plain markdown), they show as code blocks — informational, not broken.

The vault's frontmatter is the schema:

| Field | Values | Used by |
|---|---|---|
| `slug` | filename (kebab) | every query — join key |
| `status` | `draft`, `in-progress`, `in-review`, `blocked`, `shipping`, `archived` | "What am I working on?" |
| `kind` | `impl`, `proposal`, `design`, `review`, `debug`, `bugfix`, … | scope filtering |
| `project` | lowercase-kebab or `none` | per-project rollups |
| `last_updated` | `YYYY-MM-DD` | freshness sort |
| `next_action` | string | standup-shape views |
| `parent_slug` / `related[].slug` / `supersedes` / `superseded_by` / `reopens` | slug | graph queries |

All snippets scope to the `people/` folder so derived/protocol docs aren't pulled in.

---

## In-progress / in-flight

```dataview
TABLE WITHOUT ID file.link AS Task, status, project, last_updated, next_action
FROM "people"
WHERE status = "in-progress" OR status = "draft"
SORT last_updated DESC
```

## In-review (waiting on PR / approval)

```dataview
TABLE WITHOUT ID file.link AS Task, project, last_updated, next_action
FROM "people"
WHERE status = "in-review"
SORT last_updated DESC
```

## Blocked

```dataview
TABLE WITHOUT ID file.link AS Task, project, last_updated, next_action AS "Waiting on"
FROM "people"
WHERE status = "blocked"
SORT last_updated DESC
```

## Stale (active >14 days untouched)

```dataview
TABLE WITHOUT ID file.link AS Task, status, last_updated, next_action
FROM "people"
WHERE !contains(file.folder, "archive") AND status != "archived"
  AND date(today) - date(last_updated) > dur(14 days)
SORT last_updated ASC
```

## By project

Replace `"media-pipeline"` with the project slug you want.

```dataview
TABLE WITHOUT ID file.link AS Task, status, kind, last_updated
FROM "people"
WHERE project = "media-pipeline"
SORT status ASC, last_updated DESC
```

## Children of a parent task

Replace `"landing-page-rebuild"` with the parent slug.

```dataview
TABLE WITHOUT ID file.link AS Child, status, last_updated
FROM "people"
WHERE parent_slug = "landing-page-rebuild"
SORT last_updated DESC
```

## Recently updated (last 7 days)

```dataview
TABLE WITHOUT ID file.link AS Task, status, last_updated
FROM "people"
WHERE date(today) - date(last_updated) <= dur(7 days)
  AND status != "archived"
SORT last_updated DESC
```

## Shipped this week (archive scan)

```dataview
TABLE WITHOUT ID file.link AS Task, project, last_updated
FROM "people"
WHERE contains(file.folder, "archive")
  AND date(today) - date(last_updated) <= dur(7 days)
SORT last_updated DESC
```

## All tasks for a kind

Replace `"design"` with the kind you want.

```dataview
TABLE WITHOUT ID file.link AS Task, status, project, last_updated
FROM "people"
WHERE kind = "design"
SORT status ASC, last_updated DESC
```

---

## Notes for adding queries

- Always anchor with `FROM "people"`. Other paths (`docs/`, `bin/`) lack worklog frontmatter and will return junk rows.
- `WITHOUT ID` removes Obsidian's auto-prepended file column (we already include `file.link`).
- Filter by `archived` via `WHERE status != "archived"` rather than `WHERE !contains(file.folder, "archive")` when you want non-archived state regardless of folder.
- For graph-style queries (relations across multiple slugs), Dataview's `LIST FROM [[<slug>]]` works once body wikilinks are in place (see `bin/auto-slug-link.py`).
