# Serena MCP Setup

Serena provides the symbol-aware tools used by this skill. Install and initialize
the current Serena CLI first:

```bash
uv tool install -p 3.13 serena-agent
serena init
```

If an agent cannot find `serena`, replace `serena` in its configuration with the
absolute path printed by `command -v serena`.

## Claude Code

Use Serena's supported setup command:

```bash
serena setup claude-code
```

For a project-only manual setup, run this from the project root:

```bash
claude mcp add serena -- serena start-mcp-server \
  --context claude-code \
  --project "$(pwd)"
```

Run `/mcp` in Claude Code and confirm that `serena` is connected.

## Cursor

Create `.cursor/mcp.json` in the project. Replace the placeholder with the
project's absolute path:

```json
{
  "mcpServers": {
    "serena": {
      "command": "serena",
      "args": [
        "start-mcp-server",
        "--context=ide",
        "--project",
        "/absolute/path/to/project"
      ]
    }
  }
}
```

Open Cursor's MCP settings and confirm that Serena is running and its tools are
listed.

## OpenCode

OpenCode has two active configuration schemas. Check `opencode --version` and
use the matching form in `opencode.jsonc`.

OpenCode 1.x:

```json
{
  "mcp": {
    "serena": {
      "type": "local",
      "command": [
        "serena",
        "start-mcp-server",
        "--context=ide",
        "--project-from-cwd"
      ],
      "enabled": true
    }
  }
}
```

OpenCode 2.x:

```json
{
  "mcp": {
    "servers": {
      "serena": {
        "type": "local",
        "command": [
          "serena",
          "start-mcp-server",
          "--context=ide",
          "--project-from-cwd"
        ]
      }
    }
  }
}
```

Run `opencode mcp list` (1.x) or `opencode2 mcp list` (2.x) and confirm that
`serena` is connected.

## Fallback and sources

If Serena is unavailable, continue with `rg`; the skill remains usable without
symbol-aware search.

Configuration sources:

- [Serena installation and client setup](https://oraios.github.io/serena/02-usage/030_clients.html)
- [Cursor MCP configuration](https://docs.cursor.com/context/model-context-protocol)
- [OpenCode 2 MCP configuration](https://opencode.ai/v2/docs/mcp-servers)
