#!/usr/bin/env python3
"""Convert a Claude Code transcript JSONL file to readable markdown."""

import json
import sys
from datetime import datetime


def truncate(text: str, max_len: int = 200) -> str:
  if len(text) <= max_len:
    return text
  return text[:max_len] + "..."


def format_timestamp(ts: str) -> str:
  try:
    dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    return dt.strftime("%Y-%m-%d %H:%M UTC")
  except (ValueError, AttributeError):
    return ""


def format_tool_use(block: dict) -> str:
  name = block.get("name", "unknown")
  tool_input = block.get("input", {})

  if name == "Bash":
    cmd = tool_input.get("command", "")
    return f"**`$ {truncate(cmd, 300)}`**"
  elif name in ("Read", "Glob", "Grep"):
    target = tool_input.get("file_path") or tool_input.get("pattern") or ""
    return f"**{name}** `{truncate(target, 150)}`"
  elif name in ("Edit", "Write"):
    path = tool_input.get("file_path", "")
    return f"**{name}** `{path}`"
  elif name == "Task":
    desc = tool_input.get("description", "")
    return f"**Task** ({desc})"
  else:
    return f"**{name}**"


def convert(transcript_path: str) -> str:
  lines = []
  metadata_written = False
  session_id = ""
  branch = ""

  with open(transcript_path) as f:
    for raw_line in f:
      raw_line = raw_line.strip()
      if not raw_line:
        continue
      try:
        entry = json.loads(raw_line)
      except json.JSONDecodeError:
        continue

      entry_type = entry.get("type")

      if not metadata_written and entry_type == "user":
        session_id = entry.get("sessionId", "")
        branch = entry.get("gitBranch", "")
        ts = format_timestamp(entry.get("timestamp", ""))
        slug = entry.get("slug", "")
        lines.append(f"# Claude Code Session: {slug}")
        lines.append("")
        lines.append(f"- **Session ID:** `{session_id}`")
        lines.append(f"- **Branch:** `{branch}`")
        if ts:
          lines.append(f"- **Started:** {ts}")
        lines.append(f"- **Resume:** `claude --resume {session_id}`")
        lines.append("")
        lines.append("---")
        lines.append("")
        metadata_written = True

      if entry_type not in ("user", "assistant"):
        continue

      message = entry.get("message", {})
      role = message.get("role", "")
      content = message.get("content", [])

      if isinstance(content, str):
        content = [{"type": "text", "text": content}]

      for block in content:
        block_type = block.get("type")

        if block_type == "text" and block.get("text", "").strip():
          text = block["text"].strip()
          if role == "user":
            lines.append("## User")
            lines.append("")
            lines.append(text)
            lines.append("")
          elif role == "assistant":
            lines.append(text)
            lines.append("")

        elif block_type == "tool_use":
          lines.append(f"> {format_tool_use(block)}")
          lines.append("")

        elif block_type == "tool_result":
          # Skip verbose tool results — the tool_use already shows what happened
          pass

        elif block_type == "thinking":
          # Skip thinking blocks to keep output readable
          pass

  if not lines:
    return "# Empty Session\n\nNo conversation content found.\n"

  return "\n".join(lines)


if __name__ == "__main__":
  if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <transcript.jsonl>", file=sys.stderr)
    sys.exit(1)
  print(convert(sys.argv[1]))
