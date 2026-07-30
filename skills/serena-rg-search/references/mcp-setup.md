# Serena MCP Setup

This skill routes to Serena MCP tools (`find_symbol`, `find_referencing_symbols`,
`get_symbols_overview`, `search_for_pattern`). These tools are provided by an
MCP server — they are not built into the CLI agent.

## Per-project configuration

Add the Serena MCP server to your project's `.mcp.json` or equivalent:

```jsonc
{
  "mcpServers": {
    "serena": {
      // The Serena MCP server provides find_symbol, find_referencing_symbols,
      // get_symbols_overview, and search_for_pattern. Install and configure
      // the package per its documentation.
    }
  }
}
```

## Per-agent configuration

- **Claude Code**: `~/.claude/settings.json` → `mcpServers.serena`
- **Cursor**: `~/.cursor/mcp.json` → `mcpServers.serena`
- **OpenCode**: `~/.config/opencode/opencode.jsonc` → `mcpServers.serena`

## Fallback

If Serena is not activated, the skill falls back to `rg` — see line 22 of
`SKILL.md`. The skill remains usable without Serena; it just loses the
symbol-aware search pathway.