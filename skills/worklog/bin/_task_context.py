"""Pure parsing and compact projections shared by context and kernel caches."""
import datetime
import hashlib
from pathlib import Path
import re

import yaml

def parse_task_file(text: str) -> tuple[dict, str]:
  match = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.DOTALL)
  if not match:
    return {}, text
  try:
    fm = yaml.safe_load(match.group(1)) or {}
  except yaml.YAMLError:
    return {}, match.group(2)
  return fm if isinstance(fm, dict) else {}, match.group(2)


def next_section(body: str) -> str:
  """Return the current top-level `## Next` section body.

  Older checkpoint notes can contain historical `## Next` headings and
  checkboxes. Tracker hydration should mirror only the durable current plan,
  not every stale checklist ever written into the task body.
  """
  lines = body.splitlines()
  collected = []
  in_next = False

  for line in lines:
    if re.match(r"^##\s+Next\b", line):
      if in_next:
        break
      in_next = True
      continue
    if in_next and re.match(r"^##\s+", line):
      break
    if in_next:
      collected.append(line)

  return "\n".join(collected)


def parse_work_items(body: str) -> list[dict]:
  """Parse `- [ ]` / `- [x]` checkboxes, folding soft-wrapped continuation
  lines into the same bullet. A continuation line is indented further than
  the bullet marker and does not itself start a new bullet or heading."""
  items = []
  current = None
  bullet_re = re.compile(r"^(\s*)-\s*\[([ xX])\]\s+(.+?)\s*$")
  new_block_re = re.compile(r"^\s*(?:[-*#]|\d+\.)\s")
  for line in next_section(body).splitlines():
    m = bullet_re.match(line)
    if m:
      current = {
        "status": "done" if m.group(2).lower() == "x" else "open",
        "text": m.group(3),
        "_indent": len(m.group(1)) + 2,  # past "- "
      }
      items.append(current)
      continue
    if current is None:
      continue
    if not line.strip():
      current = None
      continue
    leading = len(line) - len(line.lstrip())
    if leading >= current["_indent"] and not new_block_re.match(line):
      current["text"] += " " + line.strip()
    else:
      current = None
  for it in items:
    it.pop("_indent", None)
  return items



def make_kernel(slug, fm, body, text, path, last_sha="", last_subject="", now=None, history_basis="slug-trailers"):
  now = now or datetime.datetime.now(datetime.timezone.utc)
  open_items = [w["text"] for w in parse_work_items(body) if w["status"] == "open"]
  return {
    "schema_version": "worklog-context/v1",
    "slug": str(fm.get("slug") or slug), "status": str(fm.get("status") or ""),
    "last_updated": str(fm.get("last_updated") or ""),
    "last_sha": last_sha, "last_subject": last_subject, "history_basis": history_basis,
    "next_action": str(fm.get("next_action") or ""),
    "open_items": open_items[:5], "omitted_items": max(0, len(open_items)-5),
    "task_path": str(Path(path).resolve()), "content_sha256": hashlib.sha256(text.encode()).hexdigest(),
    "generated_at": now.isoformat(timespec="seconds"),
    "expires_at": (now + datetime.timedelta(hours=1)).isoformat(timespec="seconds"),
  }


def kernel_markdown(kernel):
  def one_line(value):
    return str(value).replace("\r", "\\r").replace("\n", "\\n") or "—"
  lines = [f"slug: {kernel['slug']}", f"status: {kernel['status'] or '—'}",
           f"last_updated: {kernel['last_updated'] or '—'}",
           f"last_sha: {kernel['last_sha'] or '—'}  {one_line(kernel['last_subject'])}",
           f"next: {one_line(kernel['next_action'])}"]
  if kernel["open_items"]:
    lines.append("open:")
    lines.extend("  - " + one_line(item) for item in kernel["open_items"])
  if kernel["omitted_items"]:
    lines.append(f"omitted: {kernel['omitted_items']}")
  lines.append(f"task: {kernel['task_path']}")
  return "\n".join(lines)


def cache_freshness(records, now=None):
  """Legacy/empty lists keep the caller's mtime fallback; new records carry expiry."""
  if not isinstance(records, list) or any(not isinstance(r, dict) for r in records):
    return "invalid"
  now = now or datetime.datetime.now(datetime.timezone.utc)
  for record in records:
    if "expires_at" not in record:
      continue
    try:
      expires = datetime.datetime.fromisoformat(record["expires_at"].replace("Z", "+00:00"))
      if expires.tzinfo is None:
        return "invalid"
      if now >= expires:
        return "stale"
    except (ValueError, TypeError, AttributeError):
      return "invalid"
  return "fresh"
