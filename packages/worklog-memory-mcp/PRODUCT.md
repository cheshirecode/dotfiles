# Worklog board

Worklog is a Git-backed task journal for a person and their coding agents.
The board gives that existing journal a local visual workspace. It implements
the requested simpler alternative to adopting Kanzo's separate database.

## Users and work

People browse projects, search tasks, create work, and move it through To do,
In progress, Review, Blocked, and Done. Agents read and update those same records
through MCP. The current vault and namespace remain visible. Project filtering
works on desktop and mobile; mobile columns scroll horizontally.

## Ownership and truth

The canonical records are Markdown task files in the selected Worklog vault.
Both interfaces use the native checkpoint and archive handlers. An owned claim
requires its session ID for changes. Agents can complete their own work;
completion does not itself prove a deployment or GitHub merge. Archived records
are closed and only the latest 50 are loaded. The local board has no second
database, cloud account, or background synchronization service.

## Interface direction

Keep a quiet working interface: neutral and olive surfaces, forest action color,
system sans typography, compact legible cards, consistent SVG icons, and native
form controls. Status text accompanies color. Preserve keyboard focus through
refresh and drawer close. Errors remain visible and actual save results drive
the displayed status. The service starts on demand and binds only to loopback.
