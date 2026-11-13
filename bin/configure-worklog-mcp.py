#!/usr/bin/env python3
"""Merge managed Worklog MCP entries without replacing unrelated client settings."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile


CLIENTS = ("codex", "claude", "cursor", "opencode")


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as out:
        tmp = Path(out.name)
        try:
            os.chmod(tmp, mode)
            out.write(content)
            out.flush()
            os.fsync(out.fileno())
        except BaseException:
            tmp.unlink(missing_ok=True)
            raise
    os.replace(tmp, path)


def configure(args):
    root = Path(__file__).resolve().parent.parent
    home = Path.home()
    node = shutil.which("node")
    if not node and not (args.check or args.dry_run):
        raise ValueError("Node is unavailable; load your Node environment and rerun")
    entries = {}
    for raw in args.repo:
        vault = Path(raw).expanduser().resolve(strict=True)
        if not (vault / ".git").exists() or not (vault / "people").is_dir():
            raise ValueError(f"not a Worklog vault: {vault}")
        name = "worklog-" + hashlib.sha256(str(vault).encode()).hexdigest()[:12]
        entries[name] = {
            "command": node or "node",
            "args": [str(root / "packages/worklog-memory-mcp/server.js")],
            "env": {"WORKLOG_REPO": str(vault), "PATH": os.environ.get("PATH", os.defpath)},
        }
        entries[name]["env"]["WORKLOG_MCP_VERSION"] = "0.3.0"
    paths = {
        "codex": Path(os.environ.get("CODEX_HOME", home / ".codex")) / "config.toml",
        "claude": home / ".claude.json",
        "cursor": home / ".cursor/mcp.json",
        "opencode": Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")) / "opencode/opencode.json",
    }
    changes = []
    for client in args.client or CLIENTS:
        path = paths[client].resolve()
        old = path.read_text() if path.exists() else ""
        if client == "codex":
            new = old
            for name, entry in entries.items():
                begin = f"# dotfiles worklog MCP begin {name}"
                end = f"# dotfiles worklog MCP end {name}"
                pattern = re.compile(r"(?m)^" + re.escape(begin) + r"\n.*?^" + re.escape(end) + r"\n?", re.S)
                if (begin in new or end in new) and not pattern.search(new):
                    raise ValueError(f"incomplete managed block in {path}")
                remaining = pattern.sub("", new)
                if re.search(r"(?m)^\s*\[mcp_servers\.(?:" + re.escape(name) + '|"' + re.escape(name) + r'")\]', remaining):
                    raise ValueError(f"unmanaged server {name} in {path}; refusing to replace it")
                block = (f"{begin}\n[mcp_servers.{name}]\ncommand = {json.dumps(entry['command'])}\n"
                         f"args = {json.dumps(entry['args'])}\n[mcp_servers.{name}.env]\n"
                         + "".join(f"{key} = {json.dumps(value)}\n" for key, value in entry["env"].items())
                         + f"{end}\n")
                new = pattern.sub(lambda _: block, new) if pattern.search(new) else new.rstrip() + "\n\n" + block
        else:
            data = json.loads(old) if old.strip() else {}
            if not isinstance(data, dict):
                raise ValueError(f"expected a JSON object in {path}")
            key = "mcp" if client == "opencode" else "mcpServers"
            servers = data.setdefault(key, {})
            if not isinstance(servers, dict):
                raise ValueError(f"expected an object at {key} in {path}")
            for name, entry in entries.items():
                value = ({"type": "local", "command": [entry["command"], *entry["args"]],
                          "environment": entry["env"], "enabled": True} if client == "opencode" else entry)
                # Stable path hashes avoid collisions with named user servers.
                # Refuse a hash collision or an unrelated entry under that name.
                # Upgrade a previously configured checkout entry in place.
                # Keep its name so client allow/deny preferences remain useful.
                matches = [key for key, value in servers.items() if isinstance(value, dict)
                           and value.get("env", value.get("environment", {})).get("WORKLOG_REPO") == entry["env"]["WORKLOG_REPO"]]
                if len(matches) > 1:
                    raise ValueError(f"multiple servers already serve this vault in {path}; remove the duplicate first")
                if matches:
                    name = matches[0]
                previous = servers.get(name)
                if previous is not None and not isinstance(previous, dict):
                    raise ValueError(f"expected an object for server {name} in {path}")
                if previous and (previous.get("env", previous.get("environment", {})).get("WORKLOG_REPO") != entry["env"]["WORKLOG_REPO"]):
                    raise ValueError(f"unmanaged server {name} in {path}")
                if client == "opencode" and previous:
                    value["enabled"] = previous.get("enabled", True)
                servers[name] = {**(previous or {}), **value}
            new = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
        changes.append((path, old, new))
    link = home / ".local/bin/worklog-board"
    source = root / "bin/worklog-board"
    if link.exists() and not link.is_symlink():
        raise ValueError(f"refusing to replace an existing command: {link}")
    # All inputs must pass before the first write.
    for path, old, new in changes:
        if old == new:
            print(f"worklog-mcp: unchanged {path}")
        elif args.check or args.dry_run:
            print(f"worklog-mcp: would update {path} ({len(entries)} vaults)")
        else:
            atomic_write(path, new)
            print(f"worklog-mcp: updated {path} ({len(entries)} vaults)")
    if not (args.check or args.dry_run):
        link.parent.mkdir(parents=True, exist_ok=True)
        if not link.is_symlink() or link.resolve() != source:
            link.unlink(missing_ok=True)
            link.symlink_to(source)
        print(f"worklog-mcp: board command available at {link}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", action="append", required=True)
    parser.add_argument("--client", action="append", choices=CLIENTS)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        configure(args)
    except (ValueError, OSError, json.JSONDecodeError) as error:
        parser.exit(1, f"worklog-mcp: {error}\n")


if __name__ == "__main__":
    main()
