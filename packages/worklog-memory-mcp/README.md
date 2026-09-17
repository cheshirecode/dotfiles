# worklog-memory-mcp

> Part of [cheshirecode/dotfiles](https://github.com/cheshirecode/dotfiles) (`packages/worklog-memory-mcp`), next to the worklog skill it wraps — `WORKLOG_BIN` defaults to that sibling.

An MCP agent-memory server where memories are **task files with a state
machine**, not embeddings soup.

Generic memory servers (Mem0, Cognee, OpenMemory) store facts. Agents also
need something they don't provide: durable *work* memory — what task was in
flight, what evidence proved progress, what the next action is — that a
fresh session can hydrate and continue. That is what a git worklog vault
holds, and this server exposes it over MCP.

## Tools

| Tool | Does |
|---|---|
| `memory_search` | slug-grouped search across task bodies + frontmatter |
| `memory_context` | resume pack for a slug: frontmatter, recent commits, next action |
| `memory_task_create` | new draft task file, committed through the vault's own hooks |
| `memory_checkpoint` | append one **typed evidence line** (`command\|artifact\|git\|github\|url: ref — result`), optionally flip status, commit |

Every write goes through the worklog skill's own scripts, so vault lint and
commit hooks apply — the server invents no second rule surface. Writes are
serialized in-process (the vault lock is a single coarse lock by design;
run one server per vault).

## Use

The npm package is not published yet, so point at the checkout directly.
`WORKLOG_BIN` defaults to the sibling worklog skill, so one variable is
enough inside a dotfiles checkout:

```json
{
  "mcpServers": {
    "worklog-memory": {
      "command": "node",
      "args": ["/path/to/dotfiles/packages/worklog-memory-mcp/server.js"],
      "env": {
        "WORKLOG_REPO": "/path/to/your/worklog-vault"
      }
    }
  }
}
```

One server per vault. Give each one its own entry and its own name.

Vault conventions (task file format, FSM, slug grammar) come from the
[worklog skill](https://github.com/cheshirecode/dotfiles/tree/main/skills/worklog).

## Identity comes from the vault, not from your shell

A person usually has more than one vault — a personal one and a work one —
with a different git author, a different forge token and a different
`people/` namespace each. direnv normally keeps them apart per directory.
An MCP server breaks that assumption: the client starts it once, with the
environment of whatever directory the session began in, and it then writes
to a vault somewhere else.

So this server does not forward its own environment to the worklog scripts.
It drops every variable that carries identity, namespace or credentials
(`WORKLOG_*`, `GIT_AUTHOR_*`, `GIT_COMMITTER_*`, `GIT_USER_*`, `GIT_CONFIG*`,
`GH_*`, `GITHUB_*`, `NPM_*`, `NODE_AUTH_*`, `DIRENV_*`), then runs
`direnv exec <vault>` so the vault's own `.envrc` chain puts back the right
ones. `DIRENV_*` is dropped too, so the result does not depend on the
caller's direnv state — a client launched from a desktop icon has none.

The startup line reports which of four states applies, and they are never
collapsed into "it worked":

| `env:` | Meaning |
|---|---|
| `direnv` | the vault's `.envrc` was loaded; its values are in force |
| `scrubbed:no-envrc` | the vault has no `.envrc`; the scrub alone applies |
| `scrubbed:no-direnv` | no `.envrc` and no direnv; the scrub alone applies |
| `blocked:*` | an `.envrc` exists but could not be applied — the server **exits 78** rather than write with the wrong identity |

`blocked` is usually an un-approved file: run `direnv allow` in the vault.
Note that direnv keys its approvals by the *canonical* path, so the server
resolves symlinks in `WORKLOG_REPO` before asking.

**`WORKLOG_LDAP` is not defaulted.** It used to default to `oss`, which wrote
every task under `people/oss/` whatever the vault, and — because
`verify_provenance` in the worklog skill only compares namespace against git
email when no explicit namespace is set — switched the vault's own identity
gate off. The namespace now comes from the vault's `resolve_ldap`, the same
resolver the scripts use. A client's configured `WORKLOG_LDAP` is honoured
only for a vault that has no `.envrc` of its own; where an `.envrc` exists,
that file wins, because a value arriving in the process environment cannot
be told apart from one a sibling directory leaked.

`test/env-isolation.js` asserts all of this against a probe `bin/` that
prints the environment it was handed. It needs no vault and no network.

## Proven round trip

`test/e2e.js` clones a vault to scratch (with a local bare origin — no real
remote is ever touched), then: session A creates a task and checkpoints
typed evidence; a **separate server process** (session B) hydrates that
context and finds the evidence by search. 5 checks, run in CI against a
synthetic vault.

## Publishing (not done yet)

`server.json` is committed and validated against the MCP Registry schema
`2025-12-11`. Nothing is published. Two steps remain, and both need
credentials this repo does not hold:

1. **npm.** `server.json` points at the npm package `worklog-memory-mcp`
   at version `0.1.0`. That package is not on npm yet. Publish it first
   (`npm publish`), or the registry cannot resolve it.
2. **MCP Registry.** Then:

   ```bash
   mcp-publisher login github   # opens a browser device-code flow
   mcp-publisher publish
   ```

   The `io.github.cheshirecode/` namespace is claimed by proving you own
   the matching GitHub account, so the login step is required.

Validation itself needs no login and is safe to run at any time:

```bash
mcp-publisher validate   # ✅ server.json is valid
```

Keep the three versions in step when you cut a release: `package.json`
`version`, the top-level `version` in `server.json`, and the `version`
inside its `packages[0]` entry.
