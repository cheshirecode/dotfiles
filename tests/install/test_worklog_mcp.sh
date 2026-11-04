#!/usr/bin/env bash
# Configuration upgrade regression checks, isolated from all real client files.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
python3 "$ROOT/tests/install/worklog_mcp_config.py"
