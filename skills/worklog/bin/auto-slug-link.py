#!/usr/bin/env python3
"""Convert bare body slugs to [[wikilinks]] for Obsidian backlink/graph use.

Body-only. Frontmatter is byte-for-byte preserved (bare-slug form there is
load-bearing per AGENTS.md § Slug as join key — `bin/_index.py`, `bin/_lint.py`,
`bin/children.sh`, `bin/archive.sh` all parse bare slugs and would break
under wikilink-wrapped frontmatter).

Idempotent: running again produces no change because the converted
`[[slug]]` form is skipped by the regex.

Skip contexts:
  - inside fenced code blocks (``` ... ```)
  - inside inline code spans (`...`)
  - already wrapped in [[ ... ]]
  - inside URL/path tokens (the slug regex's negative lookarounds catch this)

Usage:
  bin/auto-slug-link.py                    # dry-run, full corpus
  bin/auto-slug-link.py --apply            # write changes in place
  bin/auto-slug-link.py --file=PATH        # scope to one file
  bin/auto-slug-link.py --slug=SLUG        # only convert mentions of this slug
"""

from __future__ import annotations

import pathlib
import re
import os
import sys

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
# Match bare slugs NOT already wrapped in [[ ... ]] and NOT inside word/path
# context. Mirrors bin/_lint.py BODY_SLUG_RE plus a negative lookbehind for `[[`.
SLUG_PATTERN = re.compile(
  r"(?<!\[\[)"
  r"(?<![A-Za-z0-9_/-])"
  r"((?:eng-\d+-)?[a-z][a-z0-9]+(?:-[a-z0-9]+){1,})"
  r"(?![A-Za-z0-9_/])"
  r"(?!\]\])"
)
FENCE_RE = re.compile(r"^```")


def resolve_root(single_file: str | None = None) -> pathlib.Path:
  env_root = os.environ.get("WORKLOG_REPO")
  if env_root and (pathlib.Path(env_root) / "people").is_dir():
    return pathlib.Path(env_root).resolve()

  cwd = pathlib.Path.cwd()
  if (cwd / "people").is_dir():
    return cwd.resolve()

  if single_file:
    candidate = pathlib.Path(single_file)
    if not candidate.is_absolute():
      candidate = cwd / candidate
    for parent in [candidate.resolve().parent, *candidate.resolve().parents]:
      if (parent / "people").is_dir():
        return parent

  return cwd.resolve()


def collect_known_slugs(people: pathlib.Path) -> set[str]:
  slugs = set()
  for ldap_dir in people.glob("*"):
    if not ldap_dir.is_dir():
      continue
    for state in ("active", "archive"):
      for path in (ldap_dir / state).glob("*.md"):
        slugs.add(path.stem)
  return slugs


def convert_body(body: str, known: set[str], scope_slug: str | None = None) -> tuple[str, int]:
  """Convert bare slugs to [[slug]] in body. Skip code blocks + inline code.

  Returns (new_body, num_changes).
  """
  out_lines = []
  changes = 0
  in_fence = False
  for line in body.split("\n"):
    if FENCE_RE.match(line):
      in_fence = not in_fence
      out_lines.append(line)
      continue
    if in_fence:
      out_lines.append(line)
      continue
    # Walk inline `...` segments, leaving them untouched.
    parts = re.split(r"(`[^`\n]*`)", line)
    for i, part in enumerate(parts):
      if part.startswith("`") and part.endswith("`"):
        continue  # inline code — leave alone

      def repl(m: re.Match[str]) -> str:
        nonlocal changes
        slug = m.group(1)
        if slug not in known:
          return slug
        if scope_slug and slug != scope_slug:
          return slug
        changes += 1
        return f"[[{slug}]]"

      parts[i] = SLUG_PATTERN.sub(repl, part)
    out_lines.append("".join(parts))
  return "\n".join(out_lines), changes


def process_file(root: pathlib.Path, path: pathlib.Path, known: set[str], apply: bool, scope_slug: str | None) -> int:
  text = path.read_text()
  m = FRONTMATTER_RE.match(text)
  if not m:
    return 0
  body = text[m.end():]
  new_body, changes = convert_body(body, known, scope_slug)
  if changes == 0:
    return 0
  if apply:
    path.write_text(text[:m.end()] + new_body)
  try:
    rel = path.resolve().relative_to(root)
  except ValueError:
    rel = path
  print(f"{'apply' if apply else 'dry-run'}: {rel} ({changes} bare → [[wikilink]])")
  return changes


def main() -> None:
  apply = False
  single_file: str | None = None
  scope_slug: str | None = None
  for arg in sys.argv[1:]:
    if arg == "--apply":
      apply = True
    elif arg.startswith("--file="):
      single_file = arg[len("--file="):]
    elif arg.startswith("--slug="):
      scope_slug = arg[len("--slug="):]
    elif arg in ("-h", "--help"):
      print(__doc__)
      sys.exit(0)
    else:
      print(f"auto-slug-link: unknown arg: {arg}", file=sys.stderr)
      sys.exit(2)

  root = resolve_root(single_file)
  people = root / "people"
  known = collect_known_slugs(people)
  if not known:
    print("auto-slug-link: no task files found under people/*/")
    sys.exit(0)

  if single_file:
    single_path = pathlib.Path(single_file)
    if not single_path.is_absolute():
      single_path = root / single_path
    paths = [single_path]
  else:
    paths = []
    for ldap_dir in sorted(people.glob("*")):
      if not ldap_dir.is_dir():
        continue
      for state in ("active", "archive"):
        paths.extend(sorted((ldap_dir / state).glob("*.md")))

  total = 0
  files = 0
  for p in paths:
    n = process_file(root, p, known, apply, scope_slug)
    if n:
      files += 1
      total += n

  verb = "would convert" if not apply else "converted"
  print(f"\nauto-slug-link: {verb} {total} bare-slug mention(s) across {files} file(s).")
  if not apply and total:
    print("Re-run with --apply to write the changes.")


if __name__ == "__main__":
  main()
