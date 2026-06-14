#!/usr/bin/env python3
"""Validate every task file under people/*/{active,archive}/.

Called by bin/lint.sh. Checks:
  - Frontmatter block exists and parses as strict YAML (warn on block-scalar
    drift even if the init-scan fallback handles it — broken YAML breaks
    downstream tooling that doesn't have the fallback).
  - `kind` ∈ documented set.
  - `status` ∈ documented FSM.
  - `project` is lowercase-kebab or literally 'none' (missing is a warning,
    not an error — some exploratory tasks genuinely have no project).
  - `last_updated` matches YYYY-MM-DD.
  - `repos` is a list (or absent).
  - Relations (`parent_slug`, `related[].slug`, `supersedes`, `superseded_by`,
    `reopens`) resolve to real task files under people/*/{active,archive}/.
  - `related[]` entries have a `note`.
  - State/status consistency: files under archive/ should have
    `status: archived` (warn if not).
  - With `--okf`, task frontmatter also has `type`, `worklog_id`, and
    `timestamp`, with `type == kind` and `last_updated == timestamp[:10]`.

With `--cross-task`, additionally checks active tasks for protocol drift:
  - `status: blocked` requires `next_action` starting "Waiting on" (FSM contract).
  - `status: in-review` >14d with no `Worklog-PR:` trailer in git log for the
    slug (stale review — PR likely landed/abandoned without status flip).
  - body mentions a known slug not declared in
    `parent_slug` / `related[].slug` / `supersedes` / `superseded_by` / `reopens`
    (undeclared cross-task ref — link rot precursor).

Exit codes:
  0 — no violations (warnings allowed).
  1 — one or more errors.
  2 — invocation error.
"""

from __future__ import annotations

import datetime
import json
import pathlib
import re
import subprocess
import sys
from typing import Any

import yaml

KINDS = {
  "design", "review", "spike", "impl", "ops", "debug",
  "program", "postmortem", "runbook", "proposal",
  # Extended ad-hoc kinds (protocol.md § Kinds permits extension):
  "bugfix", "investigation", "plan", "infra", "cleanup", "project",
  # Legacy values still in active corpus — kept additive per AGENTS.md
  # § "Kinds are additive (Liskov)". Prefer the canonical form going
  # forward (bug → debug/bugfix; perf → impl/infra; tooling → infra)
  # but do not force-rewrite shipped files.
  "bug", "perf", "tooling",
}
STATUSES = {"draft", "in-progress", "in-review", "blocked", "shipping", "archived"}
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ISO_TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:?\d{2})?$")
PROJECT_RE = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$")
SLUG_RE = re.compile(r"^(eng-\d+-)?[a-z0-9]+(-[a-z0-9]+)*$")

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
BODY_SLUG_RE = re.compile(r"(?<![A-Za-z0-9_/-])(?:eng-\d+-)?[a-z][a-z0-9]+(?:-[a-z0-9]+){1,}(?![A-Za-z0-9_/])")
STALE_REVIEW_DAYS = 14


def _collect(root: pathlib.Path) -> list[tuple[pathlib.Path, str]]:
  out = []
  for ldap_dir in sorted((root / "people").glob("*")):
    if not ldap_dir.is_dir():
      continue
    for state in ("active", "archive"):
      for path in sorted((ldap_dir / state).glob("*.md")):
        out.append((path, state))
  return out


def _strict_yaml(raw: str) -> tuple[dict[str, Any] | None, str | None]:
  try:
    fm = yaml.safe_load(raw)
    if not isinstance(fm, dict):
      return None, "frontmatter did not parse as a mapping"
    return fm, None
  except yaml.YAMLError as e:
      return None, f"YAML parse error: {str(e).splitlines()[0]}"


def _date_from_timestamp(value: Any) -> str | None:
  if isinstance(value, datetime.datetime):
    return value.date().isoformat()
  if isinstance(value, datetime.date):
    return value.isoformat()
  if not isinstance(value, str):
    return None
  value = value.strip()
  if DATE_RE.match(value):
    return value
  if not ISO_TS_RE.match(value):
    return None
  return value[:10]


def _slugs_with_pr_trailers() -> set[str]:
  """Return slugs that have at least one Worklog-PR: trailer in git log."""
  try:
    out = subprocess.check_output(
      ["git", "log", "--all", "--format=%(trailers:key=Worklog-Slug,valueonly=true,separator=%x09)%x1f%(trailers:key=Worklog-PR,valueonly=true,separator=%x09)"],
      text=True, stderr=subprocess.DEVNULL,
    )
  except (subprocess.CalledProcessError, FileNotFoundError):
    return set()
  hits: set[str] = set()
  for line in out.splitlines():
    if "\x1f" not in line:
      continue
    slug_part, pr_part = line.split("\x1f", 1)
    if not pr_part.strip():
      continue
    for s in slug_part.split("\t"):
      s = s.strip()
      if s:
        hits.add(s)
  return hits


def _latest_status_trailers() -> dict[str, str]:
  """Map slug → most recent Worklog-Status: trailer value from git log.

  Slug detection: explicit Worklog-Slug: trailer first; else subject prefix
  matching `<slug>:` (covers checkpoint/archive/status-flip commits). Walks
  newest-first; first hit per slug wins.
  """
  try:
    out = subprocess.check_output(
      ["git", "log", "--all",
       "--format=%s%x1f%(trailers:key=Worklog-Slug,valueonly=true,separator=%x09)%x1f%(trailers:key=Worklog-Status,valueonly=true,separator=%x09)%x1e"],
      text=True, stderr=subprocess.DEVNULL,
    )
  except (subprocess.CalledProcessError, FileNotFoundError):
    return {}
  out_map: dict[str, str] = {}
  for record in out.split("\x1e"):
    record = record.strip("\n ")
    if not record:
      continue
    parts = record.split("\x1f", 2)
    if len(parts) < 3:
      continue
    subject, slug_trailer, status_trailer = parts
    status = status_trailer.split("\t")[0].strip() if status_trailer.strip() else ""
    if not status:
      continue
    slugs: set[str] = set()
    for s in slug_trailer.split("\t"):
      s = s.strip()
      if s:
        slugs.add(s)
    if not slugs:
      m = re.match(r"^([a-z][a-z0-9-]+):\s", subject)
      if m:
        slugs.add(m.group(1))
    for s in slugs:
      out_map.setdefault(s, status)
  return out_map


def _missing_related_slugs(fm: dict[str, Any], body: str, slug: str, known_slugs: set[str]) -> list[str]:
  """Return body-mention slugs (sorted) not declared in any relation field."""
  declared: set[str] = set()
  for k in ("parent_slug", "supersedes", "superseded_by", "reopens"):
    v = fm.get(k)
    if v:
      declared.add(str(v))
  for item in fm.get("related") or []:
    if isinstance(item, dict) and item.get("slug"):
      declared.add(str(item["slug"]))
  declared.add(slug)
  missing = {t for t in BODY_SLUG_RE.findall(body) if t in known_slugs and t not in declared}
  return sorted(missing)


def _stub_related_block(missing: list[str], indent: str = "  ") -> str:
  """Build a YAML `related:` block (or appendable items) for the given slugs.

  `indent` is the leading whitespace for the `- slug:` line. `note:` is
  indented two spaces deeper. Both indent-0 (`- slug:` at column 0) and
  indent-2 (`  - slug:`) are valid YAML sequence styles for the parent
  mapping — but they MUST NOT MIX within a single block. The caller
  passes the indent observed in the existing block; default is 2 (the
  canonical style for the corpus).
  """
  note_indent = indent + "  "
  return "".join(
    f"{indent}- slug: {s}\n{note_indent}note: \"(auto-added; refine note)\"\n"
    for s in missing
  )


def _apply_fix_related(path: pathlib.Path, missing: list[str]) -> bool:
  """Append missing slugs to related: in the file's frontmatter.

  Returns True if the file was modified. Preserves existing frontmatter
  text byte-for-byte; only inserts inside or before the closing `---`.
  Refuses to edit if related: is in inline-list form (rare in this corpus).
  """
  if not missing:
    return False
  text = path.read_text()
  m = FRONTMATTER_RE.match(text)
  if not m:
    return False
  fm_text = m.group(1)
  fm_end = m.end()  # position of char after the closing "---\n"
  body_after = text[fm_end:]

  lines = fm_text.split("\n")
  # Find existing related: block (block-style only). Look for a line that is
  # exactly "related:" at column 0, then siblings keys at column 0 mark the end.
  related_idx: int | None = None
  for i, line in enumerate(lines):
    if re.match(r"^related:\s*$", line):
      related_idx = i
      break
    if re.match(r"^related:\s*\[", line):
      # inline-list form — refuse to edit
      return False

  if related_idx is None:
    # Insert a new `related:` block at the end of the frontmatter
    # (before closing ---). Existing frontmatter ends with the last key
    # at column 0 followed by its value(s); we just append. New blocks
    # use indent-2 (corpus-canonical style).
    stub_items = _stub_related_block(missing, indent="  ")
    new_fm_text = fm_text.rstrip("\n") + "\n" + "related:\n" + stub_items.rstrip("\n")
  else:
    # Detect the existing block's indent style by inspecting the first
    # `- slug:` line under `related:`. Both indent-0 (`- slug:` at col 0)
    # and indent-2 are valid YAML, but they MUST NOT MIX in one block —
    # YAML errors at the indent boundary. Match the detected style on
    # insert. Default to indent-2 if no existing items.
    existing_indent = "  "
    for j in range(related_idx + 1, len(lines)):
      m_item = re.match(r"^(\s*)- slug:", lines[j])
      if m_item:
        existing_indent = m_item.group(1)
        break
      # Hit a column-0 key that's not a sequence item → block is empty
      if lines[j] and not lines[j].startswith((" ", "\t", "-")):
        break

    # Find block-end. A line is INSIDE the block iff it is either:
    #   - a sequence-item line at the detected item indent (`<indent>- ...`)
    #   - a continuation line at strictly deeper indent (note value, etc.)
    #   - a blank line
    # Anything else (a sibling key at the same or shallower indent than
    # `related:`) marks the block end. `related:` itself is at column 0,
    # so sibling keys are also at column 0.
    item_indent_len = len(existing_indent)
    end_idx = len(lines)
    for j in range(related_idx + 1, len(lines)):
      line = lines[j]
      if not line.strip():
        continue
      lead = len(line) - len(line.lstrip(" \t"))
      stripped = line[lead:]
      if lead == item_indent_len and stripped.startswith("- "):
        continue  # sequence item line, inside block
      if lead > item_indent_len:
        continue  # continuation (note value), inside block
      end_idx = j
      break

    stub_items = _stub_related_block(missing, indent=existing_indent)
    insertion = stub_items.rstrip("\n").split("\n")
    new_lines = lines[:end_idx] + insertion + lines[end_idx:]
    new_fm_text = "\n".join(new_lines)

  new_text = "---\n" + new_fm_text + "\n---\n" + body_after
  path.write_text(new_text)
  return True


def _cross_task_checks(
  fm: dict[str, Any],
  body: str,
  state: str,
  slug: str,
  known_slugs: set[str],
  slugs_with_pr: set[str],
  today: datetime.date,
  latest_status_trailers: dict[str, str] | None = None,
) -> tuple[list[str], list[str]]:
  errors: list[str] = []
  warnings: list[str] = []
  if state != "active":
    return errors, warnings

  status = fm.get("status")
  next_action = fm.get("next_action") or ""
  last_updated_raw = fm.get("last_updated")

  # 1. blocked → next_action must start "Waiting on"
  if status == "blocked" and isinstance(next_action, str):
    if not next_action.lstrip().lower().startswith("waiting on"):
      errors.append("status 'blocked' but next_action does not start with 'Waiting on' (FSM contract, AGENTS.md § Status lifecycle)")

  # 2a. trailer-vs-frontmatter divergence: latest Worklog-Status: trailer
  # for this slug must match frontmatter status. Drift here means a commit
  # author hand-wrote a trailer (e.g. via `git commit -m`) without flipping
  # the frontmatter — bypassing bin/checkpoint.sh --status=, which is the
  # only path that updates both atomically. Warning, not error: there are
  # legitimate cases (force-push fixups, multi-task commits) where a brief
  # divergence is fine.
  if latest_status_trailers and isinstance(status, str):
    trailer_status = latest_status_trailers.get(slug)
    if trailer_status and trailer_status not in STATUSES:
      errors.append(
        f"latest Worklog-Status: trailer '{trailer_status}' for this slug is not in FSM: {sorted(STATUSES)}"
      )
    elif trailer_status and trailer_status != status:
      warnings.append(
        f"frontmatter status '{status}' diverges from latest "
        f"Worklog-Status: trailer '{trailer_status}' for this slug — "
        f"use `bin/checkpoint.sh {slug} --status={trailer_status}` to align"
      )

  # 2. stale in-review: in-review >14d with no Worklog-PR: trailer for slug
  if status == "in-review" and isinstance(last_updated_raw, str) and DATE_RE.match(last_updated_raw):
    try:
      last_dt = datetime.date.fromisoformat(last_updated_raw)
      age_days = (today - last_dt).days
      if age_days >= STALE_REVIEW_DAYS and slug not in slugs_with_pr:
        warnings.append(f"status 'in-review' for {age_days}d with no Worklog-PR: trailer for this slug — flip to in-progress / shipping or attach a PR")
    except ValueError:
      pass

  # 3. body mentions a known slug not in declared relations.
  # Umbrella tasks that resolve children via grep on parent_slug opt out by
  # including the exact phrase "Children are derived, not listed" in the body
  # — heuristic warning would fire on every child reference and add no signal.
  if "Children are derived, not listed" not in body:
    declared: set[str] = set()
    for k in ("parent_slug", "supersedes", "superseded_by", "reopens"):
      v = fm.get(k)
      if v:
        declared.add(str(v))
    for item in fm.get("related") or []:
      if isinstance(item, dict) and item.get("slug"):
        declared.add(str(item["slug"]))
    declared.add(slug)  # self-mentions are fine

    for token in set(BODY_SLUG_RE.findall(body)):
      if token in known_slugs and token not in declared:
        warnings.append(f"body mentions slug '{token}' not in parent_slug/related/supersedes/reopens — declare the relation or remove the reference")

  return errors, warnings


def _lint_file(
  path: pathlib.Path,
  state: str,
  known_slugs: set[str],
  cross_task: bool = False,
  okf: bool = False,
  slugs_with_pr: set[str] | None = None,
  today: datetime.date | None = None,
  latest_status_trailers: dict[str, str] | None = None,
) -> tuple[list[str], list[str]]:
  errors: list[str] = []
  warnings: list[str] = []
  text = path.read_text()
  m = FRONTMATTER_RE.match(text)
  if not m:
    errors.append("missing frontmatter block")
    return errors, warnings

  fm, err = _strict_yaml(m.group(1))
  if err:
    errors.append(err)
    return errors, warnings
  assert fm is not None

  slug = fm.get("slug")
  if not slug:
    errors.append("missing frontmatter key: slug")
  elif not SLUG_RE.match(str(slug)):
    errors.append(f"slug '{slug}' does not match grammar ^(eng-\\d+-)?[a-z0-9]+(-[a-z0-9]+)*$")

  kind = fm.get("kind")
  if not kind:
    errors.append("missing frontmatter key: kind")
  elif kind not in KINDS:
    # Active/ tasks must use the current taxonomy; archive/ is frozen history
    # and may carry legacy kinds (task, feature, fix, content, refactor, ...).
    # Mirrors the project: precedent below — archive is silently grandfathered.
    if state == "active":
      errors.append(f"kind '{kind}' not in documented set: {sorted(KINDS)}")
    # No warning for archive entries — legacy kinds are expected there and
    # rewriting frozen history is exactly what archives are meant to prevent.

  status = fm.get("status")
  if not status:
    errors.append("missing frontmatter key: status")
  elif status not in STATUSES:
    errors.append(f"status '{status}' not in FSM: {sorted(STATUSES)}")

  if state == "archive" and status and status != "archived":
    warnings.append(f"file under archive/ has status '{status}' (expected 'archived')")
  if state == "active" and status == "archived":
    errors.append("status 'archived' but file is under active/")

  project = fm.get("project")
  if project is None or project == "":
    # Archive/ tasks are frozen history — don't pester about missing project there.
    if state == "active":
      warnings.append("missing project: (use 'none' if intentional)")
  else:
    if not (project == "none" or PROJECT_RE.match(str(project))):
      errors.append(f"project '{project}' is not lowercase-kebab or 'none'")

  last_updated = fm.get("last_updated")
  if not last_updated:
    errors.append("missing frontmatter key: last_updated")
  elif not DATE_RE.match(str(last_updated)):
    errors.append(f"last_updated '{last_updated}' is not YYYY-MM-DD")

  if okf:
    okf_type = fm.get("type")
    if not okf_type:
      errors.append("missing OKF frontmatter key: type")
    elif kind and str(okf_type) != str(kind):
      errors.append(f"OKF type '{okf_type}' must match kind '{kind}' for task files")

    worklog_id = fm.get("worklog_id")
    if not worklog_id:
      errors.append("missing OKF frontmatter key: worklog_id")
    elif "/" not in str(worklog_id):
      errors.append(f"worklog_id '{worklog_id}' must be namespaced")

    timestamp = fm.get("timestamp")
    timestamp_date = _date_from_timestamp(timestamp)
    if not timestamp:
      errors.append("missing OKF frontmatter key: timestamp")
    elif not timestamp_date:
      errors.append(f"timestamp '{timestamp}' is not OKF ISO timestamp format")
    elif last_updated and DATE_RE.match(str(last_updated)) and str(last_updated) != timestamp_date:
      errors.append(f"last_updated '{last_updated}' disagrees with timestamp date '{timestamp_date}'")

  next_action = fm.get("next_action")
  if not next_action:
    errors.append("missing frontmatter key: next_action")
  elif isinstance(next_action, str) and "\n" in next_action:
    errors.append("next_action must be a single-line string; move detail to the `## Next` body section")

  repos = fm.get("repos", [])
  if repos is not None and not isinstance(repos, list):
    errors.append(f"repos must be a list, got {type(repos).__name__}")

  for rel_key in ("parent_slug", "supersedes", "superseded_by", "reopens"):
    target = fm.get(rel_key)
    if target and str(target) not in known_slugs:
      errors.append(f"{rel_key}: '{target}' does not resolve to a known task file")

  related = fm.get("related", [])
  if related is not None and not isinstance(related, list):
    errors.append(f"related must be a list, got {type(related).__name__}")
  else:
    for i, item in enumerate(related or []):
      if not isinstance(item, dict):
        errors.append(f"related[{i}] must be a mapping")
        continue
      if "slug" not in item:
        errors.append(f"related[{i}] missing 'slug'")
      elif str(item["slug"]) not in known_slugs:
        errors.append(f"related[{i}].slug '{item['slug']}' does not resolve")
      if not item.get("note"):
        errors.append(f"related[{i}] missing 'note' (required to prevent link rot)")
      elif "auto-added" in str(item.get("note", "")) and "refine note" in str(item.get("note", "")):
        warnings.append(f"related[{i}].note is the auto-generated placeholder — replace with a one-line *why* (relation purpose, not a body-mention rephrase)")

  # Advisory: notion.so URL in external_refs: but no notion: field — init --full won't match it.
  if state == "active" and not fm.get("notion"):
    ext_refs = fm.get("external_refs", []) or []
    if isinstance(ext_refs, list):
      if any("notion.so" in str(r) for r in ext_refs):
        warnings.append("external_refs: contains a notion.so URL but notion: field is absent — add 'notion: <page-id>' so init --full can match this task")

  body = text[m.end():]
  if state == "active":
    if "\n## Context" not in f"\n{body}":
      warnings.append("missing ## Context section")
    if "\n## Next" not in f"\n{body}":
      warnings.append("missing ## Next section")
  elif state == "archive" and status == "archived":
    if not re.search(r"^Archived \d{4}-\d{2}-\d{2}:", body, re.MULTILINE):
      warnings.append("archived task missing 'Archived YYYY-MM-DD:' marker")

  if cross_task and slug and isinstance(slug, str):
    ct_errors, ct_warnings = _cross_task_checks(
      fm, body, state, slug, known_slugs,
      slugs_with_pr or set(),
      today or datetime.date.today(),
      latest_status_trailers=latest_status_trailers,
    )
    errors.extend(ct_errors)
    warnings.extend(ct_warnings)

  return errors, warnings


def main() -> None:
  fmt = "md"
  single_file: str | None = None
  cross_task = False
  okf = False
  fix_related = False
  for arg in sys.argv[1:]:
    if arg in ("--format=md", "--format=markdown"):
      fmt = "md"
    elif arg == "--format=json":
      fmt = "json"
    elif arg.startswith("--file="):
      single_file = arg[len("--file="):]
    elif arg == "--cross-task":
      cross_task = True
    elif arg == "--okf":
      okf = True
    elif arg == "--fix-related":
      # --fix-related implies --cross-task (the missing-related lint runs
      # only in cross-task mode). It auto-stubs missing slug references
      # into each file's `related:` block with a placeholder note.
      cross_task = True
      fix_related = True
    elif arg in ("-h", "--help"):
      print(__doc__)
      sys.exit(0)
    else:
      print(f"lint: unknown arg: {arg}", file=sys.stderr)
      sys.exit(2)

  root = pathlib.Path.cwd()
  # Always collect all files — known_slugs must span the whole corpus for
  # relation resolution — then narrow the lint loop if --file was passed.
  all_files = _collect(root)
  if single_file:
    target = pathlib.Path(single_file)
    if not target.is_absolute():
      target = (root / target).resolve()
    try:
      target_rel = target.relative_to(root)
    except ValueError:
      print(f"lint: --file must be inside {root}", file=sys.stderr)
      sys.exit(2)
    files = [(p, s) for p, s in all_files if p.resolve() == target]
    if not files:
      print(f"lint: --file {target_rel} is not a tracked task file", file=sys.stderr)
      sys.exit(2)
  else:
    files = all_files
  known_slugs: set[str] = set()
  for path, _ in all_files:
    text = path.read_text()
    m = FRONTMATTER_RE.match(text)
    if not m:
      known_slugs.add(path.stem)
      continue
    try:
      fm = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError:
      fm = {}
    if isinstance(fm, dict) and fm.get("slug"):
      known_slugs.add(str(fm["slug"]))
    else:
      known_slugs.add(path.stem)

  slugs_with_pr = _slugs_with_pr_trailers() if cross_task else set()
  latest_status_trailers = _latest_status_trailers() if cross_task else {}
  today = datetime.date.today()

  fixed_files: list[tuple[str, list[str]]] = []
  if fix_related:
    for path, state in files:
      if state != "active":
        continue
      text = path.read_text()
      m = FRONTMATTER_RE.match(text)
      if not m:
        continue
      fm, _ = _strict_yaml(m.group(1))
      if fm is None:
        continue
      slug = fm.get("slug") or path.stem
      body = text[m.end():]
      missing = _missing_related_slugs(fm, body, str(slug), known_slugs)
      if missing and _apply_fix_related(path, missing):
        fixed_files.append((str(path.relative_to(root)), missing))

  report: list[dict[str, Any]] = []
  total_errors = 0
  total_warnings = 0
  for path, state in files:
    errors, warnings = _lint_file(
      path, state, known_slugs,
      cross_task=cross_task,
      okf=okf,
      slugs_with_pr=slugs_with_pr,
      today=today,
      latest_status_trailers=latest_status_trailers,
    )
    total_errors += len(errors)
    total_warnings += len(warnings)
    if errors or warnings:
      report.append({
        "file": str(path.relative_to(root)),
        "state": state,
        "errors": errors,
        "warnings": warnings,
      })

  if fmt == "json":
    print(json.dumps({
      "total_files": len(files),
      "files_with_issues": len(report),
      "total_errors": total_errors,
      "total_warnings": total_warnings,
      "issues": report,
    }, indent=2))
  else:
    if fixed_files:
      print(f"--fix-related applied: {len(fixed_files)} file(s) modified")
      for f, slugs in fixed_files:
        print(f"  {f}")
        for s in slugs:
          print(f"    + related: {s}  (auto-added; refine note)")
      print()
    print(f"Scanned {len(files)} task files — {total_errors} errors, {total_warnings} warnings")
    print()
    for item in report:
      print(f"{item['file']}  [{item['state']}]")
      for e in item["errors"]:
        print(f"  ERROR   {e}")
      for w in item["warnings"]:
        print(f"  warn    {w}")
      print()

  sys.exit(1 if total_errors else 0)


if __name__ == "__main__":
  main()
