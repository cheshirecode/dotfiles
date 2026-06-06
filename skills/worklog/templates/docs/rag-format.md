# RAG format — why this repo is just markdown + git

The worklog is an agent-consumed knowledge store: across sessions, across machines, across agents (Claude Code, Codex, Cursor). It is also a git repo. This doc explains the format choice and what *not* to add.

## Design constraints

1. **Git-native.** Every state change is a commit; history is the audit trail. Binary or churn-heavy formats break this.
2. **Agent-readable without a server.** An agent with filesystem access + ripgrep should be able to retrieve everything relevant. No MCP server required, no vector DB required.
3. **Multi-agent.** Claude, Codex, Cursor must all read the same source of truth. Rules out agent-specific binary indexes.
4. **Diffable.** A human reviewing `git diff` should see meaningful changes, not reshuffled embedding rows.
5. **Cross-machine.** `git pull` must fully sync. No machine-local caches masquerading as truth.

## What we use: markdown + YAML frontmatter + stable slugs

- **Markdown body** — prose sections with fixed headings (`## Context`, `## Invariants`, `## Next`). Agents read these directly.
- **YAML frontmatter** — coarse filter: `slug`, `status`, `kind`, `repos`, `linear`, `project`, `last_updated`, `parent_slug`, `related`. `grep`/`rg` on these fields is the retrieval primitive.
- **Stable slugs** — content-addressable: `people/<ldap>/active/<slug>.md`. Cross-references are bare slugs; any grep joins without path-parsing.
- **JSON manifests on demand** — `bin/init-scan.sh --format=json`, `bin/status.sh --format=json`, `bin/context.sh --format=json` emit computed views. Never committed.

This is Zettelkasten plus frontmatter. The primary retrieval engine is ripgrep — fast, deterministic, no model dependency, no drift between what's on disk and what's "indexed."

## What we deliberately do NOT commit

- **Embedding vectors.** A 1536-dim float vector per chunk bloats the repo, churns on every model swap, and produces unreadable diffs. The *source text* is in git; embeddings are a derivative.
- **Binary vector indexes** (FAISS, Annoy, HNSW). Rebuild-all-or-nothing; machine-specific; defeats `git blame`.
- **SQLite knowledge stores** (Chroma, txtai-style). Binary, single-writer, hard to review.
- **Agent-specific cache files.** `~/.claude/projects/<hash>/…`, Codex session logs, Cursor history. These are per-machine state, not durable knowledge.

**Rule:** text in git, derivatives in local gitignored caches, rebuildable from text.

## Retrieval tiers (what agents should reach for, in order)

Three tiers, cheapest first. Each tier stays available on its own — higher tiers are add-ons, not replacements.

### Tier 1 — `ripgrep` (always on, no setup)

Primary retrieval engine. Covers ~95% of "fetch the task I'm thinking of" queries because frontmatter tags (`project:`, `linear:`, `kind:`, `status:`) are stable vocabulary. Patterns agents should know:

```bash
rg --type md '^status: in-review' people/<ldap>/active/
rg --type md -l '\bauth\b' people/*/active/ | xargs rg '^project:'
rg -B1 -A2 'preview deploy' people/*/archive/
```

Works for every agent (Claude, Codex, Cursor) with zero setup. Available on every machine. Requirement on bootstrap: `rg --version` succeeds.

### Tier 2 — structure-aware semantic via serena MCP

Serena's LSP-backed `find_symbol` / `get_symbols_overview` work on markdown too — headings become a symbol tree. Good when you know the *shape* of what you want but not the keyword:

- "show me every task's `## Invariants` section across the project"
- "list every slug under `people/<ldap>/active/`" (same as `rg --files` but with structure grouping)
- "find the `## Next` block of tasks tagged `kind: impl`"

Multi-agent: serena is an MCP server, so every MCP-capable client can use it — **Claude Code, Codex (CLI and App), Cursor, VSCode assistants, JetBrains, Gemini-CLI** all have documented integrations (see [oraios/serena](https://github.com/oraios/serena) Quick Start). Bootstrap check: configure the serena MCP per the client's setup docs; if the agent has no MCP support or the server is unreachable, fall back to `rg` with heading anchors (`rg -A5 '^## Invariants' people/*/`).

### Tier 3 — local gitignored hybrid index (BM25 + dense), escape hatch

Use when tiers 1-2 miss concept queries repeatedly:

- "Find prior tasks about *flaky preview deploys*" — concept match, not keyword match.
- "What decisions have we made about *carve-out fallback behavior*" — scattered mentions, no single tag.

Design (not yet built — trigger is ≥3 concept-search failures in a week):

1. `bin/embed.sh` — reads `people/*/*/*.md`, emits `.cache/embeddings.jsonl` (gitignored). Chunk by `## ` section, not by token window. Prepend a one-sentence context blurb per chunk (Anthropic's contextual-retrieval pattern, ~35% lift over naive embeddings).
2. `bin/search.sh "<query>"` — BM25 + dense hybrid over the cache, optional cross-encoder rerank. Returns `{slug, section, score}` rows.
3. Works alongside tiers 1-2, doesn't replace them: agent keeps reaching for `rg` first, falls to search.sh only when concept match matters.
4. Re-embed is a single script; model swaps cost minutes.

**Do not commit the cache.** `.cache/` stays gitignored. The source text is in git; embeddings are a derivative. Every machine rebuilds its own cache.

### When to build tier 3

Don't build speculatively. Triggers:
- Concept-match failures recur (logged in a `search-misses.log` under `.cache/`).
- Archive count passes a threshold where linear-scan `rg` over `people/*/archive/` stops feeling instant.
- Cross-task "what have we decided about X" queries become routine.

Until then, tiers 1-2 are the full retrieval story.

## Conventions we align with

- **`AGENTS.md`** (cross-agent convention, OpenAI/Anthropic-aligned). Auto-loaded by Codex; surfaced via kickoff prompt for Claude. Lives at repo root and optionally in subdirectories.
- **`SKILL.md`** (Anthropic). Progressive disclosure: metadata triggers load, body fetched on demand. Used in `ui/.claude/skills/` and `ui/.agents/skills/`.
- **`llms.txt`** (emerging, Answer.ai). Project-level site map for LLMs. Not in use here — `AGENTS.md` covers the same role with more structure.
- **MCP resources** (Anthropic). Protocol for servers exposing file/resource lists to agents. The underlying storage is still markdown/JSON — MCP is transport, not format.

## Compact rule

If it can't be read by `cat`, diffed by `git diff`, and queried by `rg`, don't put it in `_worklog/`.
