---
name: browser-use-setup
description: Install, upgrade, wrap, and connect the browser-use CLI across macOS and Linux, with sandbox-safe testing and platform-specific debugging.
---

# browser-use-setup

Use when browser automation needs installing, upgrading, or connecting: the
uv-managed `browser-use` CLI, its vendor skill registration, and the browser
connection gate. For day-to-day browser work use the vendor `browser-use`
skill this skill installs — this skill owns setup, not usage.

## Install

Run `bin/install-browser-use.sh` (from this skill's directory). Flags:

- `--bootstrap-uv` — install uv first if missing (default: refuse with exit 2)
- `--no-skill` — skip `browser-use skill install` (vendor skill registration)
- `--strict-doctor` — fail the script when the post-install doctor is unhealthy

Sandbox-safe: the script honors `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`, and `HOME`,
so a test install never touches the real one.

## Wrapper

`bin/bu [--ensure] <args…>` locates the CLI across PATH layouts and execs it.
`--ensure` runs the installer first when the binary is missing.

## Platform notes

Read `references/platforms.md` when the install or connection fails, when on
Linux/headless/CI, or before the first connection on a new machine. Do not preload it.
