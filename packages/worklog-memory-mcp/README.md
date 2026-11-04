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

Twelve tools cover task memory and project claims. Read the table top to bottom: that
is the order a cold session uses them.

| Tool | Use it when | Wraps | What it costs to maintain |
|---|---|---|---|
| `memory_status` | resuming with no slug in hand — "what was I doing?" | `status.sh` | Widest flag surface (`--since --slug --project --format --include-meta`); most exposed to flag drift |
| `memory_related` | before creating a task, to find prior art and the project slugs in use | `related-search.sh` | Two flags. Output is a grep report, so its shape is loose by design |
| `memory_search` | you know a phrase but not the slug | `search.sh` | No flags passed. The safest wrapper |
| `memory_context` | you know the slug and want the resume pack | `context.sh` | One flag. `--tracker` is not exposed — the caller is the tracker |
| `memory_task_create` | no task file exists yet | writes the file, then `checkpoint.sh` | **Highest.** The frontmatter template lives in this server, so a vault schema change breaks it silently. `memory_lint` is the guard |
| `memory_checkpoint` | record one typed evidence line; optionally flip status | `checkpoint.sh` | Two flags. Refuses an archived task |
| `memory_archive` | the task is done — cancelled or superseded work | `archive.sh` | Three flags. Requires a summary, which the script only warns about |
| `memory_projects` | discover project queues | `project.sh list` | Read-only |
| `memory_next` | inspect the next eligible task without claiming it | `project.sh next --json` | Read-only |
| `memory_claim` | acquire or renew a task for one caller session | `project.sh claim` | Native dependency checks, namespace guard, and claim arbitration |
| `memory_release` | release a claim owned by the caller | `project.sh release` | Same explicit session ID required |
| `memory_lint` | check a task, or sweep the vault, without writing | `lint.sh` | Three flags. Read-only |

Every write goes through the worklog skill's own scripts, so vault lint and
commit hooks apply — the server invents no second rule surface. Writes are
serialized in-process (the vault lock is a single coarse lock by design; run
one server per vault).

Two rules worth knowing before you call anything:

- **`archived` is reachable only through `memory_archive`.** Setting the status
  in frontmatter is not the transition: the file has to move from `active/` to
  `archive/`. That is why `memory_checkpoint`'s status list stops at `shipping`.
- **An archived task is a closed record.** `memory_checkpoint` refuses one
  rather than appending to it.

## What still needs the worklog skill

These tools cover the task lifecycle. They are not the whole skill, and are not
meant to be. Eight of the skill's thirteen public modes stay out, each for a
stated reason in `coverage.json`:

| Mode | Why it is not a tool |
|---|---|
| `plan`, `spawn`, `review` | Reasoning and text generation. The model does this work; there is no vault operation to wrap |
| `init`, `export`, `import` | Machine and session setup, not task memory. `memory_status` covers the part a cold agent actually needs |
| `scrape-slack` | An external integration behind a mandatory human review gate |
| `help` | The MCP client lists tools itself |
| `project` | Discovery, selection, claim, and release are tools. Create or edit project graphs through `project.sh`. |

## Setup and upgrades

From the dotfiles checkout, run `bin/install-worklog-mcp.sh`. It discovers
existing vaults through Worklog's bootstrap probe. Use `--repo /path/to/vault`
(repeatable) for an explicit selection, and `--client codex|claude|cursor|opencode`
(repeatable) to select clients. The default configures all four clients.
`--dry-run` validates inputs without installing dependencies or writing files.

The installer uses the lockfile and records an absolute Node executable.
Run it from your normal Node environment. It keeps a suitable user Node
(>=20.11) and npm. If those are absent or too old, it installs a private
Node 22 runtime from nodejs.org after verifying the release checksum. It
also prepares an isolated Python environment when PyYAML is absent. These
fallbacks live under `~/.local/share/worklog-mcp` (or `XDG_DATA_HOME`). Each
vault gets its own server entry; vault identity is still resolved at startup.
Other servers and client settings stay in place. Repeated setup preserves
unchanged configuration bytes. JSON entries for the same vault are upgraded
under their existing names. Existing invalid or conflicting settings fail
before any configuration is written. Review and approve an existing `.envrc`
yourself when direnv requires it; the installer does not approve shell code.
Restart the affected clients after setup.

Both dotfiles installer entry points configure existing vaults. The Worklog
installer also configures a newly bootstrapped vault. `DOTFILES_NO_WORKLOG_MCP=1`
skips MCP setup from the top-level dotfiles installer; `bin/install.sh --no-worklog`
skips the Worklog installation step. The package remains internal-only: no
npm publication or MCP Registry publication is part of setup.

## Compact reads and claims

`memory_context` defaults to `for=compact` and returns the existing
`worklog-context/v1` JSON pack. Use `for=resume` or `for=review` for more detail.
Read tools have `max_chars` (default 8000, maximum 64000). Truncated results
say how to retrieve more; they are not complete JSON documents. Search returns
at most `top` hits (default 20, maximum 50). Narrow the pattern to find omitted
matches. Errors remain errors when output is shortened.

Call `memory_projects`, then `memory_next` to inspect a project. To acquire
work, call `memory_claim` with exactly one of `slug` or `project`, and a unique
`session_id`. A project claim selects and acquires an eligible child through
the existing Worklog helper. Reuse the session ID after a restart, on renewal,
on `memory_checkpoint`, and on `memory_release`. Never share an ID between
agents. Competing callers retain the native lock, dependency, Git arbitration,
and project `stale_after` behavior. A failed claim does not authorize work.
A checkpoint on a claimed task requires the owning session ID.

## Human acceptance

Agents submit completed work with `memory_checkpoint(status="shipping")`,
review evidence, and a next action naming the required human review.
`memory_archive` refuses `reason=shipped` and `reason=merged`; a user accepts
through the existing `archive.sh` CLI after reviewing the evidence. Other
archive reasons remain available for unclaimed cancelled or superseded work.
This is a boundary on the MCP mutation interface. It is not authentication
against an agent that also has unrestricted shell or filesystem access.

## Dogfood

`bin/dogfood-worklog-mcp.sh` exercises a new vault, first and repeat setup,
configured desktop-style startup, and the protocol suite in a disposable HOME.
It does not change real vaults or client configuration. With the sibling
sandbox running, use `../sandbox/bin/sandbox.sh test-worklog` to run the same
checks as `dev` on Linux and retain the full log.

## Keeping the two in step

The skill is upstream and moves on its own schedule. Nothing here can stop
that, so `test/surface-sync.js` makes drift loud instead. It reads the skill's
own `modes/registry.md` — the same marked block `codex-surface-check.sh`
consumes — and checks four directions plus the flags:

| Drift | Caught by |
|---|---|
| the skill adds a mode | it is unclassified in `coverage.json` |
| the skill drops a mode | `coverage.json` still classifies it |
| a tool named here does not exist | checked against the live `tools/list` |
| the server grows a tool nothing explains | same check, other direction |
| a script renames a flag this server passes | each flag must still appear in that script's `--help` |

Flag drift is the one that matters most in practice. A name check cannot see
it: the tool keeps building its argv right up to the moment the script rejects
it, and the failure lands in someone's session instead of in CI.

Each exemption names **one literal mode** and carries its reason. A glob or a
prefix would quietly exempt whatever the skill adds next, which is the failure
this file exists to prevent.

When the check fails, the fix is a decision, not a silence: wrap the new mode
in a tool, or exempt it by name and write down why.

If the skill's `bin/` or `modes/registry.md` cannot be found, the suite reports
`NOT RUN` / `NOT CHECKED` and exits 2. It never reports a pass for something it
did not assert.

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
