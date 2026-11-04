#!/usr/bin/env bash
# Install the private Worklog MCP adapter and merge per-vault client entries.
# Usage: bin/install-worklog-mcp.sh [--repo PATH]... [--client NAME]... [--dry-run]
# Clients: codex, claude, cursor, opencode (default: all four).
# With no --repo, discover existing vaults using Worklog's bootstrap probe.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
args=()
dry=0
explicit=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) args+=(--repo "${2:?--repo needs a path}"); explicit=1; shift ;;
    --client) args+=(--client "${2:?--client needs a name}"); shift ;;
    --dry-run) dry=1; args+=(--dry-run) ;;
    -h|--help) sed -n '2,5p' "$0" | sed 's/^# //'; exit 0 ;;
    *) echo "install-worklog-mcp: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
if [[ "$explicit" -eq 0 ]]; then
  probe="$("$ROOT/skills/worklog/bin/bootstrap.sh" probe)"
  while IFS=$'\t' read -r label vault rest; do
    [[ "$label" == vault ]] || continue
    args+=(--repo "$vault")
  done <<< "$probe"
fi
if [[ "${#args[@]}" -eq 0 ]] || ! printf '%s\n' "${args[@]}" | grep -qx -- '--repo'; then
  echo "install-worklog-mcp: no vault found; run /worklog init, then rerun this installer."
  exit 0
fi
# Validate config and all vaults before dependencies or configuration change.
python3 "$ROOT/bin/configure-worklog-mcp.py" "${args[@]}" --check
if [[ "$dry" -eq 1 ]]; then
  echo "install-worklog-mcp: would install locked npm dependencies and configure clients."
  exit 0
fi
node_bin="$(python3 "$ROOT/bin/worklog-mcp-node.py")"
if [[ "${PATH%%:*}" != "${node_bin%/*}" ]]; then PATH="${node_bin%/*}:$PATH"; fi
export PATH
# Desktop clients do not inherit shell-only PYTHONPATH. Use an isolated Python
# fallback when the selected interpreter cannot import Worklog's YAML reader.
if ! env -u PYTHONPATH -u PYTHONHOME python3 -c 'import yaml' >/dev/null 2>&1; then
  pyenv="${XDG_DATA_HOME:-$HOME/.local/share}/worklog-mcp/python"
  python3 -m venv "$pyenv"
  "$pyenv/bin/python3" -m pip install --disable-pip-version-check --no-input 'PyYAML==6.0.3' >&2
  export PATH="$pyenv/bin:$PATH"
fi
python3 - "$ROOT/packages/worklog-memory-mcp" <<'PY'
import fcntl
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile

package = Path(sys.argv[1])
lock = Path(tempfile.gettempdir()) / ("worklog-mcp-install-" + hashlib.sha256(str(package).encode()).hexdigest() + ".lock")
with lock.open("w") as handle:
    fcntl.flock(handle, fcntl.LOCK_EX)
    digest = hashlib.sha256((package / "package-lock.json").read_bytes() + (package / "package.json").read_bytes()).hexdigest()
    stamp = package / "node_modules/.worklog-install.sha256"
    healthy = stamp.exists() and stamp.read_text() == digest
    if healthy:
        healthy = subprocess.run(["npm", "ls", "--all", "--omit=dev"], cwd=package, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if not healthy:
        result = subprocess.run(["npm", "ci", "--ignore-scripts", "--no-audit", "--no-fund", "--prefer-offline", "--fetch-retries=1", "--fetch-timeout=30000"], cwd=package, stdout=sys.stderr)
        if result.returncode:
            sys.exit(result.returncode)
        stamp.write_text(digest)
    else:
        print("install-worklog-mcp: locked dependencies already healthy")
PY
python3 "$ROOT/bin/configure-worklog-mcp.py" "${args[@]}"
