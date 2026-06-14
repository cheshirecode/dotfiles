#!/usr/bin/env python3
"""OKF compatibility tools for the worklog corpus.

The worklog protocol remains slug/task oriented. This module adds the OKF
source-bundle fields that make the corpus interoperable without breaking
existing readers:

  - task files keep `kind`, `status`, `last_updated`, `next_action`, etc.
  - task files also get `type`, `worklog_id`, and `timestamp`.
  - for task files, `type` is kept equal to `kind`.
  - when `timestamp` and `last_updated` disagree, `timestamp` wins.

Usage:
  okf.py sync-task people/$USER/active/<slug>.md --date YYYY-MM-DD
  okf.py migrate --repo /path/to/_worklog [--apply]
  okf.py doctor --repo /path/to/_worklog
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import re
import subprocess
import sys
from typing import Any

import yaml

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n?", re.DOTALL)
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ISO_TS_RE = re.compile(
  r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:?\d{2})?$"
)
GENERATED_OR_LOCAL_PARTS = {
  ".cache",
  ".agents",
  ".claude",
  ".cursor",
  ".ruff_cache",
  "node_modules",
}


def _read(path: pathlib.Path) -> str:
  return path.read_text(encoding="utf-8")


def _write(path: pathlib.Path, text: str) -> None:
  path.write_text(text, encoding="utf-8")


def _repo_namespace(root: pathlib.Path) -> str:
  env_ns = os.environ.get("WORKLOG_NAMESPACE")
  if env_ns:
    return env_ns
  parts = root.resolve().parts
  if "Documents" in parts and "oss" in parts and root.name == "_worklog":
    return "oss"
  if "Documents" in parts and "projects" in parts and root.name == "_worklog":
    return "projects"
  if root.name == "_worklog":
    return root.parent.name
  return root.name


def _split_frontmatter(text: str) -> tuple[str, str, bool]:
  match = FRONTMATTER_RE.match(text)
  if match:
    return match.group(1), text[match.end():], True
  return "", text, False


def _parse_frontmatter(raw: str) -> dict[str, Any]:
  if not raw.strip():
    return {}
  parsed = yaml.safe_load(raw)
  return parsed if isinstance(parsed, dict) else {}


def _yaml_quote(value: str) -> str:
  return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _set_fm_field(fm_raw: str, field: str, value: str) -> str:
  pattern = re.compile(rf"^{re.escape(field)}:.*(?:\n[ \t]+.*)*$", re.MULTILINE)
  replacement = f"{field}: {value}"
  if pattern.search(fm_raw):
    return pattern.sub(lambda _m: replacement, fm_raw, count=1)
  fm_raw = fm_raw.rstrip("\n")
  return f"{fm_raw}\n{replacement}" if fm_raw else replacement


def _set_fields(text: str, fields: list[tuple[str, str]]) -> str:
  fm_raw, body, _had_fm = _split_frontmatter(text)
  for field, value in fields:
    fm_raw = _set_fm_field(fm_raw, field, value)
  body_prefix = "" if body.startswith("\n") or not body else "\n"
  return f"---\n{fm_raw.rstrip()}\n---\n{body_prefix}{body}"


def _date_from_timestamp(value: Any) -> str | None:
  if isinstance(value, dt.datetime):
    return value.date().isoformat()
  if isinstance(value, dt.date):
    return value.isoformat()
  if not isinstance(value, str):
    return None
  value = value.strip()
  if DATE_RE.match(value):
    return value
  if not ISO_TS_RE.match(value):
    return None
  return value[:10]


def _timestamp_from_date(date_value: str) -> str:
  return f"{date_value}T00:00:00Z"


def _git_output(root: pathlib.Path, args: list[str]) -> str:
  return subprocess.check_output(
    ["git", "-C", str(root), *args],
    text=True,
    stderr=subprocess.DEVNULL,
  )


def _git_last_timestamp(root: pathlib.Path, rel: pathlib.Path) -> str | None:
  try:
    out = _git_output(root, ["log", "-1", "--format=%cI", "--", str(rel)])
  except (subprocess.CalledProcessError, FileNotFoundError):
    return None
  value = out.strip()
  if not value:
    return None
  return value


def _tracked_markdown(root: pathlib.Path) -> list[pathlib.Path]:
  try:
    out = _git_output(root, ["ls-files", "*.md"])
    paths = [root / line for line in out.splitlines() if line.strip()]
  except (subprocess.CalledProcessError, FileNotFoundError):
    paths = sorted(root.glob("**/*.md"))
  return [
    p for p in paths
    if not any(part in GENERATED_OR_LOCAL_PARTS for part in p.relative_to(root).parts)
  ]


def _first_heading(text: str, fallback: str) -> str:
  _fm_raw, body, _had_fm = _split_frontmatter(text)
  for line in body.splitlines():
    if line.startswith("# "):
      title = line[2:].strip()
      if title:
        return title
  return fallback.replace("-", " ").replace("_", " ").strip().title() or fallback


def _task_info(root: pathlib.Path, path: pathlib.Path) -> tuple[str, str, str] | None:
  try:
    rel = path.relative_to(root)
  except ValueError:
    return None
  parts = rel.parts
  if len(parts) >= 4 and parts[0] == "people" and parts[2] in {"active", "archive"}:
    return parts[1], parts[2], path.stem
  return None


def _classify_non_task(root: pathlib.Path, path: pathlib.Path, fm: dict[str, Any]) -> tuple[str, str, bool]:
  rel = path.relative_to(root)
  parts = rel.parts
  if parts[0] == "projects":
    return str(fm.get("kind") or "project-view"), "project-view", False
  if len(parts) >= 4 and parts[0] == "people" and parts[2] == "transcripts":
    return str(fm.get("kind") or "transcript"), "transcript", False
  if len(parts) >= 4 and parts[0] == "people" and parts[2] == "shipped":
    return str(fm.get("kind") or "legacy-shipped-record"), "legacy-shipped", False
  if parts[0] == "docs":
    return str(fm.get("kind") or "protocol-doc"), "protocol-doc", True
  if parts[0] == "bin":
    return str(fm.get("kind") or "helper-doc"), "helper-doc", True
  return str(fm.get("kind") or "protocol-doc"), "protocol-doc", True


def _worklog_id(root: pathlib.Path, path: pathlib.Path, fm: dict[str, Any]) -> str:
  namespace = _repo_namespace(root)
  task = _task_info(root, path)
  if task:
    owner, _state, slug = task
    return str(fm.get("worklog_id") or f"{namespace}/{owner}/{fm.get('slug') or slug}")
  rel_no_suffix = path.relative_to(root).with_suffix("")
  return str(fm.get("worklog_id") or f"{namespace}/{rel_no_suffix.as_posix()}")


def _timestamp_for_file(
  root: pathlib.Path,
  path: pathlib.Path,
  fm: dict[str, Any],
  date_override: str | None = None,
) -> str:
  if date_override:
    return _timestamp_from_date(date_override)
  existing_ts = fm.get("timestamp")
  if existing_ts:
    if isinstance(existing_ts, dt.datetime):
      iso = existing_ts.isoformat()
      return iso[:-6] + "Z" if iso.endswith("+00:00") else iso
    if isinstance(existing_ts, dt.date):
      return _timestamp_from_date(existing_ts.isoformat())
    return str(existing_ts)
  last_updated = fm.get("last_updated")
  if isinstance(last_updated, dt.date):
    return _timestamp_from_date(last_updated.isoformat())
  if isinstance(last_updated, str) and DATE_RE.match(last_updated):
    return _timestamp_from_date(last_updated)
  rel = path.relative_to(root)
  return _git_last_timestamp(root, rel) or _timestamp_from_date(dt.date.today().isoformat())


def sync_task_text(
  root: pathlib.Path,
  path: pathlib.Path,
  text: str,
  date_override: str | None = None,
) -> tuple[str, bool]:
  fm_raw, _body, _had_fm = _split_frontmatter(text)
  fm = _parse_frontmatter(fm_raw)
  task = _task_info(root, path)
  if not task:
    raise ValueError(f"{path} is not under people/*/{{active,archive}}/")

  _owner, _state, slug_from_path = task
  kind = str(fm.get("kind") or fm.get("type") or "task")
  slug = str(fm.get("slug") or slug_from_path)
  timestamp = _timestamp_for_file(root, path, fm, date_override=date_override)
  timestamp_date = _date_from_timestamp(timestamp)
  if not timestamp_date:
    fallback_date = date_override or dt.date.today().isoformat()
    timestamp = _timestamp_from_date(fallback_date)
    timestamp_date = fallback_date

  fields = [
    ("slug", slug),
    ("kind", kind),
    ("type", kind),
    ("worklog_id", _worklog_id(root, path, {**fm, "slug": slug})),
    ("timestamp", timestamp),
    ("last_updated", timestamp_date),
  ]
  updated = _set_fields(text, fields)
  return updated, updated != text


def sync_source_text(root: pathlib.Path, path: pathlib.Path, text: str) -> tuple[str, bool]:
  fm_raw, _body, _had_fm = _split_frontmatter(text)
  fm = _parse_frontmatter(fm_raw)
  task = _task_info(root, path)
  if task:
    return sync_task_text(root, path, text)

  okf_type, entity, authoritative = _classify_non_task(root, path, fm)
  if fm.get("kind"):
    okf_type = str(fm["kind"])
  timestamp = _timestamp_for_file(root, path, fm)
  timestamp_date = _date_from_timestamp(timestamp)
  if not timestamp_date:
    timestamp = _git_last_timestamp(root, path.relative_to(root)) or _timestamp_from_date(dt.date.today().isoformat())
    timestamp_date = _date_from_timestamp(timestamp) or dt.date.today().isoformat()

  fields: list[tuple[str, str]] = [
    ("type", okf_type),
    ("worklog_entity", entity),
    ("worklog_id", _worklog_id(root, path, fm)),
    ("timestamp", timestamp),
    ("title", _yaml_quote(str(fm.get("title") or _first_heading(text, path.stem)))),
    ("worklog_authoritative", "true" if authoritative else "false"),
  ]
  if fm.get("last_updated"):
    fields.append(("last_updated", timestamp_date))
  updated = _set_fields(text, fields)
  return updated, updated != text


def cmd_sync_task(args: argparse.Namespace) -> int:
  root = pathlib.Path(args.repo or os.environ.get("WORKLOG_REPO") or pathlib.Path.cwd()).resolve()
  path = pathlib.Path(args.file)
  if not path.is_absolute():
    path = root / path
  path = path.resolve()
  updated, changed = sync_task_text(root, path, _read(path), date_override=args.date)
  if changed:
    _write(path, updated)
  print(json.dumps({"file": str(path.relative_to(root)), "changed": changed}, indent=2))
  return 0


def cmd_migrate(args: argparse.Namespace) -> int:
  root = pathlib.Path(args.repo).resolve()
  changed: list[str] = []
  scanned = 0
  for path in _tracked_markdown(root):
    scanned += 1
    text = _read(path)
    updated, did_change = sync_source_text(root, path, text)
    if did_change:
      changed.append(str(path.relative_to(root)))
      if args.apply:
        _write(path, updated)
  print(json.dumps({
    "repo": str(root),
    "scanned": scanned,
    "changed": len(changed),
    "applied": bool(args.apply),
    "files": changed,
  }, indent=2))
  return 1 if changed and args.check else 0


def cmd_doctor(args: argparse.Namespace) -> int:
  root = pathlib.Path(args.repo).resolve()
  errors: list[str] = []
  warnings: list[str] = []

  if not (root / "people").is_dir():
    warnings.append("people/ directory not found; this does not look like a data worklog repo")

  try:
    hook_path = _git_output(root, ["config", "--get", "core.hooksPath"]).strip()
  except (subprocess.CalledProcessError, FileNotFoundError):
    hook_path = ""
  if hook_path:
    hook_abs = pathlib.Path(hook_path)
    if not hook_abs.is_absolute():
      hook_abs = root / hook_abs
    if not hook_abs.exists():
      errors.append(f"core.hooksPath points at missing path: {hook_path}")
  else:
    warnings.append("core.hooksPath is not set")

  try:
    status = _git_output(root, ["status", "--porcelain", "--untracked-files=all"]).splitlines()
  except (subprocess.CalledProcessError, FileNotFoundError):
    status = []
  local_noise = [
    line for line in status
    if any(f"/{part}/" in f"/{line[3:]}/" or line[3:] == part for part in GENERATED_OR_LOCAL_PARTS)
  ]
  if local_noise:
    warnings.append(f"local/generated files are visible to git status: {', '.join(local_noise[:5])}")

  dry_args = argparse.Namespace(repo=str(root), apply=False, check=False)
  pending: list[str] = []
  for path in _tracked_markdown(root):
    updated, did_change = sync_source_text(root, path, _read(path))
    if did_change:
      pending.append(str(path.relative_to(root)))
  if pending:
    errors.append(f"OKF migration pending for {len(pending)} markdown file(s)")

  print(json.dumps({
    "repo": str(root),
    "errors": errors,
    "warnings": warnings,
    "pending_okf_files": pending,
  }, indent=2))
  return 1 if errors else 0


def main() -> None:
  parser = argparse.ArgumentParser(description="Worklog OKF compatibility tools")
  sub = parser.add_subparsers(dest="cmd", required=True)

  sync = sub.add_parser("sync-task", help="sync OKF fields on one task file")
  sync.add_argument("file")
  sync.add_argument("--repo")
  sync.add_argument("--date", help="YYYY-MM-DD date to use for timestamp/last_updated")
  sync.set_defaults(func=cmd_sync_task)

  migrate = sub.add_parser("migrate", help="migrate tracked markdown files to OKF frontmatter")
  migrate.add_argument("--repo", required=True)
  migrate.add_argument("--apply", action="store_true")
  migrate.add_argument("--check", action="store_true", help="exit 1 when dry-run finds changes")
  migrate.set_defaults(func=cmd_migrate)

  doctor = sub.add_parser("doctor", help="preflight hook/local-state/OKF readiness")
  doctor.add_argument("--repo", required=True)
  doctor.set_defaults(func=cmd_doctor)

  args = parser.parse_args()
  if getattr(args, "date", None) and not DATE_RE.match(args.date):
    print("okf: --date must be YYYY-MM-DD", file=sys.stderr)
    sys.exit(2)
  sys.exit(args.func(args))


if __name__ == "__main__":
  main()
