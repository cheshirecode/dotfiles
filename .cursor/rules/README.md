# Cursor Configuration

This directory contains configuration files for Cursor, an AI-powered code editor.

## Files

- `rules/` - Contains rule files that define behavior for the Cursor AI assistant
  - `01-guidelines.mdc` - Basic guidelines for the assistant
  - `02-collaborator-profile.mdc` - Collaborator profile for coding tasks
  - `03-hyperecho.mdc` - Configuration for non-coding tasks or when 'hyperecho' keyword is included
  - `04-typescript-expo.mdc` - Configuration for TypeScript and Expo tasks
  - `05-auto-dev.mdc` - Configuration for the automated development process

- `mcp.json` - Configuration for Model Context Protocol (MCP) servers

## MCP Configuration

The `mcp.json` file configures Model Context Protocol servers used by Cursor. This allows for specialized AI capabilities like sequential thinking and external API integrations.

### Default Configuration

```json
{
  "mcpServers": {
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "veyrax-mcp": {
      "command": "npx",
      "args": [
        "-y",
        "@smithery/cli@latest",
        "run",
        "@VeyraX/veyrax-mcp",
        "--config",
        "\"{ \\\"VEYRAX_API_KEY\\\": \\\"YOUR_API_KEY_HERE\\\" }\""
      ]
    }
  }
}
```

### Setup

To use this configuration:

1. Copy the `mcp.json` file to your Cursor settings directory
2. Replace `YOUR_API_KEY_HERE` with your actual VeyraX API key (if using that service)
3. Restart Cursor to apply the changes

## Auto-dev Feature

The auto-dev feature (configured in `rules/05-auto-dev.mdc`) provides an automated development workflow. To use it:

1. Start a message with `auto-dev!` followed by your instruction
2. The assistant will use sequential thinking to analyze the task
3. It will automatically manage git operations, track progress in project-tracker.md, and execute appropriate development steps

## Notes

- Keep API keys and sensitive information secure when sharing this configuration
- You may need to install dependencies for the MCP servers to function:
  ```
  npm install -g @modelcontextprotocol/server-sequential-thinking
  npm install -g @smithery/cli
  ```
