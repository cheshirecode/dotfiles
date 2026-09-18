# Vendor skill registration

Verified against browser-use 0.1.13 on 2026-09-18: `browser-use skill install`
defaults to `--target all`. Its vendor installer writes separate `SKILL.md`
files under `.agents/skills/browser-use` and `.codex/skills/browser-use`, as well
as other assistant roots. Codex can discover both, producing duplicate catalog
entries even when the files have identical contents. These are installed vendor
usage instructions. The dotfiles-owned `browser-use-setup` is a separate skill
for installation and connection maintenance.

The setup installer calls `bin/register-browser-use-skills.sh`, which explicitly
registers the shared agents target and the other vendor targets, omitting the
redundant Codex target. `--no-install` avoids a second uv upgrade after the
parent installer has already installed the package.

Before registration, the helper archives a legacy Codex directory only if it
contains exactly one ordinary `SKILL.md` identical to the existing shared copy.
Symlinks, different contents and extra files are preserved for inspection.
Backups live under `~/.local/state/browser-use-setup/duplicate.*/browser-use`,
outside all skill discovery roots. To undo, move that exact backup directory
back to `.codex/skills/browser-use` only if the destination is absent.

To repair registration without reinstalling the CLI:

```bash
bash bin/register-browser-use-skills.sh "$(command -v browser-use)"
```

Run it from this skill's directory in the user's shell environment. An active
task may retain its original skill catalog until a new task/session discovers
skills again. Running the vendor's bare `skill install` later can recreate the
duplicate; use the setup helper for future registration.
