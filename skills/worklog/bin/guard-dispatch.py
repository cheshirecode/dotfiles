#!/usr/bin/env python3
"""PreToolUse dispatcher for guards that live outside this skill.

The skill owns the mechanism; the guards are injected. Each directory on
WORKLOG_GUARDS_PATH (os.pathsep-separated; install-hooks.sh sets it to
<data repo>/people/<namespace>/guards) may hold guard modules:

    TOOLS = ("Bash",)            # optional: tool names this guard sees
    def check(event: dict) -> str | None:
        ...                      # a deny reason, or None to allow

`event` is the hook JSON Claude Code sends (tool_name, tool_input, cwd, ...).
Files named `_*.py` or `test_*.py` are not guards (helpers and their tests).

The first deny wins and is printed as a PreToolUse deny decision. A guard that
fails to load or raises denies with that error, naming the file: a guard that
stops working must not read as a guard that found nothing.

Trust: only load guards from your own namespace. A guard is code that runs on
every matching tool call.
"""
from __future__ import annotations

import glob
import importlib.util
import json
import os
import sys
from typing import Optional


def guard_files(path_var: str) -> list[str]:
    files = []
    for d in [p for p in path_var.split(os.pathsep) if p]:
        for f in sorted(glob.glob(os.path.join(d, "*.py"))):
            name = os.path.basename(f)
            if not (name.startswith("_") or name.startswith("test_")):
                files.append(f)
    return files


def _load(path: str):
    name = "worklog_guard_" + os.path.splitext(os.path.basename(path))[0]
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, os.path.dirname(path))  # a guard may import its own _helpers
    try:
        spec.loader.exec_module(module)
    finally:
        sys.path.remove(os.path.dirname(path))
    return module


def dispatch(event: dict, path_var: str) -> Optional[str]:
    tool = event.get("tool_name") or ""
    for path in guard_files(path_var):
        label = os.path.basename(path)
        try:
            module = _load(path)
            tools = getattr(module, "TOOLS", None)
            if tools is not None and tool not in tools:
                continue
            reason = module.check(event)
        except Exception as e:  # noqa: BLE001 - reported as a deny, never swallowed
            return f"guard {label} failed ({type(e).__name__}: {e}); fix or remove it"
        if reason:
            return f"[{label}] {reason}"
    return None


def main() -> int:
    path_var = os.environ.get("WORKLOG_GUARDS_PATH", "")
    if not path_var:
        return 0
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    reason = dispatch(event, path_var)
    if reason:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
