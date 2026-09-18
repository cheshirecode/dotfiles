# Machine-local secrets

One file holds every credential on every machine: `~/.env.secrets`.

`install.sh` creates it from `templates/env.secrets.example` on first run, at
mode `0600`, with every key empty. You fill it in per machine. The installer
never writes a value and never overwrites the file, so a re-run is safe.

This is the pattern Coder documents for workspace secrets: give the user their
secrets in advance, and have them write them to a persistent file after the
workspace is built. A dotfiles repo cannot carry values that differ per
machine, and must not carry values at all.

## Format

Dotenv. One `KEY=value` per line. No `export`, no shell expansion, no quotes
needed. That is the shape direnv's own `dotenv_if_exists` reads, and the same
shape `~/.hermes/.env` already uses, so nothing new had to be invented.

```
GH_TOKEN_CHESHIRECODE=
NPM_TOKEN=
ANTHROPIC_API_KEY=
```

Keys are named by owner where an account is involved. `GH_TOKEN_CHESHIRECODE`,
not `GH_TOKEN`: one machine holds tokens for more than one account, and the
tree you are standing in decides which applies.

Leave a key empty rather than deleting it. An empty key documents what this
machine could hold. A missing one looks like an oversight.

## Reading it

| Command | What it does |
| --- | --- |
| `bin/env-secret.sh KEY` | prints one value, `rc 1` if absent |
| `bin/with-secrets.sh KEY -- cmd` | runs `cmd` with `KEY` exported, nothing else |

Both read **one key at a time**. Nothing sources the file globally, and that is
the point: `.envrc` gives each directory tree its own identity, so a credential
exported in a login shell would be present in every tree, including work
checkouts. Per-command is the smallest scope that still works where there is no
keychain.

`with-secrets.sh` also renames: `GH_TOKEN:GH_TOKEN_CHESHIRECODE` exports the
owner-scoped value as the plain `GH_TOKEN` a tool expects.

## Where the file lives

| Platform | Path |
| --- | --- |
| macOS, Linux, Coder workspace | `~/.env.secrets` |
| WSL | `~/.env.secrets` on the **Linux** filesystem |
| Windows, no WSL (Git Bash, PowerShell) | `%USERPROFILE%\.env.secrets` |
| anywhere | `$ENV_SECRETS_FILE` overrides |

The readers try `$ENV_SECRETS_FILE`, then `$HOME`, then `$USERPROFILE`.

**A Windows drive mounted into WSL (`/mnt/c/...`) is deliberately not on that
list.** DrvFs reports `0777` whatever you `chmod`, so a credential there cannot
be made unreadable to other Windows accounts — and a read from it would look
exactly like a read from a safe file. Keep the file on the Linux side.

NTFS has no `0600`. On Windows without WSL, restrict it to your account:

```
icacls "%USERPROFILE%\.env.secrets" /inheritance:r /grant:r "%USERNAME%:R"
```

Both readers print a warning when the file's mode is not `600` or `400`. They
still return the value: refusing would break a caller mid-task, and the
operator needs to see the cause rather than a missing token.

## Precedence, and why a keychain still wins

`resolve_gh_token()` in `.envrc.example` tries, in order:

1. `gh auth token`
2. `pass show github.com/<owner>`
3. macOS keychain
4. `~/.env.secrets`, key `GH_TOKEN_<OWNER>`

The file is **last** on purpose. A Mac keeps its secret out of cleartext, while
Linux, WSL and Coder workspaces — which have no keychain — still resolve a
token from the same dotfiles. Where a tool can do its own browser login, prefer
that and leave the key empty: those sessions live in the tool's own config,
which is safer than a key in a file.

## Agent CLIs

Only needed where the CLI cannot do a browser login: WSL, Git Bash, a headless
box, or a container.

```
with-secrets.sh ANTHROPIC_API_KEY  -- claude
with-secrets.sh OPENROUTER_API_KEY -- opencode
with-secrets.sh CURSOR_API_KEY     -- cursor-agent
```

## In the sandbox container

`../sandbox` does not use this file directly. It pipes each credential through
a tmpfs at `/run/secrets/<name>_token` at mode `0400`, so nothing shows up in
`docker inspect` and nothing is written to a host temp file. Its host-side
probes cascade env var, then dotenv file, then keychain; `~/.env.secrets` joins
that cascade as the last step, which is why the format matches.

## What this replaced

Four holders with no shared shape:

- `~/.github_token` — plaintext at mode `0644`, `cat`-ed by `.shell_common`
- a PAT written straight into a per-tree `.envrc`
- `.envrc.github` — gitignored, referenced by the installer, never created
- `.shell_common.vault` — a tracked overlay in a public repo

`.shell_common.*` is now ignored as a class, not as a list of remembered
names, so the next suffix cannot be tracked by accident. `.shell_common`
itself stays tracked.

## Gotcha worth keeping

The template is `templates/env.secrets.example`, **not**
`.env.secrets.example`. The `.env.*` rule in `.gitignore` would have ignored
the latter: it would look tracked in your working tree while being absent from
every fresh clone, so `install.sh` would silently create nothing.
`tests/install/test_secret_files_untracked.sh` asserts the template is tracked
for exactly this reason.
