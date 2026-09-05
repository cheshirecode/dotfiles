#!/opt/homebrew/bin/python3
"""Normalize Claude PostToolUse payloads for the shared PR cost collector."""

from __future__ import annotations

import json
import subprocess
import sys
from typing import Any


PYTHON = "/opt/homebrew/bin/python3"
COLLECTOR = "/Users/fredtran/Documents/oss/dotfiles/skills/pr-cost/scripts/pr_cost_collect.py"


def _clean_string(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    stripped = value.strip()
    return stripped or None


def _clean_int(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value


def _clean_number(value: Any) -> float | int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return value


def _exit_code(tool_response: dict[str, Any]) -> int | None:
    explicit_exit = _clean_int(tool_response.get("exit_code"))
    if explicit_exit is not None:
        return explicit_exit
    if tool_response.get("interrupted") is True:
        return 130
    return None


def normalize_payload(payload: dict[str, Any]) -> dict[str, Any]:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        tool_input = {}

    tool_response = payload.get("tool_response")
    if not isinstance(tool_response, dict):
        tool_response = {}

    stdout = tool_response.get("stdout")
    normalized = {
        "command": _clean_string(tool_input.get("command")),
        "stdout": stdout if isinstance(stdout, str) else "",
        "exit_code": _exit_code(tool_response),
    }

    stderr = tool_response.get("stderr")
    if isinstance(stderr, str):
        normalized["stderr"] = stderr

    return normalized


def collector_command(payload: dict[str, Any]) -> list[str]:
    command = [PYTHON, COLLECTOR, "from-hook", "--harness", "claude"]

    session_id = _clean_string(payload.get("session_id"))
    if session_id is not None:
        command.extend(["--session-id", session_id])

    model = _clean_string(payload.get("model"))
    if model is not None:
        command.extend(["--model", model])

    generated_at = _clean_string(payload.get("timestamp"))
    if generated_at is not None:
        command.extend(["--generated-at", generated_at])

    usd = _clean_number(payload.get("usd"))
    if usd is not None:
        command.extend(["--usd", str(usd)])

    tokens_in = _clean_int(payload.get("tokens_in"))
    if tokens_in is not None:
        command.extend(["--tokens-in", str(tokens_in)])

    tokens_out = _clean_int(payload.get("tokens_out"))
    if tokens_out is not None:
        command.extend(["--tokens-out", str(tokens_out)])

    return command


def main() -> int:
    raw_input = sys.stdin.read()
    if not raw_input.strip():
        return 0

    try:
        payload = json.loads(raw_input)
    except json.JSONDecodeError:
        return 0

    if not isinstance(payload, dict):
        return 0

    try:
        subprocess.run(
            collector_command(payload),
            input=json.dumps(normalize_payload(payload)),
            text=True,
            capture_output=True,
            check=False,
        )
    except Exception:
        return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
