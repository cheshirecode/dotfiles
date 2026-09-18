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

Registration uses the shared `.agents/skills/browser-use` copy for Codex.
An identical, single-file `.codex/skills/browser-use` duplicate is archived
outside discovery roots; customized copies are preserved. See
[skill-registration.md](references/skill-registration.md) for recovery.

## Wrapper

`bin/bu [--ensure] <args…>` locates the CLI across PATH layouts and execs it.
`--ensure` runs the installer first when the binary is missing. On WSL with a
Windows-side browser, `bu` probes the gateway portproxy and localhost CDP
endpoints and exports `BU_CDP_URL` itself; caller-set `BU_CDP_URL`,
`BU_CDP_WS`, or `BU_NAME` always win.

## WebMCP integration

For site-provided tools alongside browser navigation, read
[webmcp.md](references/webmcp.md). It distinguishes the legacy webmcp.dev bridge
from the current browser API and provides a read-only capability probe.

## Platform notes

Read `references/platforms.md` when the install or connection fails, when on
Linux/headless/CI, or before the first connection on a new machine. Do not preload it.
