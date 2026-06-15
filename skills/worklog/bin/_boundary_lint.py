#!/usr/bin/env python3
"""Scan a worklog clone for content that violates its boundary profile."""

from __future__ import annotations

import argparse
import fnmatch
import glob
import json
import pathlib
import re
import sys
from dataclasses import dataclass
from typing import Any


DEFAULT_INCLUDES = [
    "people/*/active/*.md",
    "people/*/archive/*.md",
    "projects/*.md",
]


@dataclass(frozen=True)
class DenyPattern:
    pattern: str
    note: str = ""


@dataclass(frozen=True)
class AllowPattern:
    path: str
    pattern: str


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Scan task/project markdown for cross-domain terms declared in "
            ".worklog-boundary.json."
        )
    )
    parser.add_argument("--repo", default=".", help="worklog repo root (default: cwd)")
    parser.add_argument(
        "--config",
        default=None,
        help="boundary profile JSON (default: <repo>/.worklog-boundary.json)",
    )
    parser.add_argument(
        "--include",
        action="append",
        default=[],
        help="glob relative to repo to scan; may repeat",
    )
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        help="glob relative to repo to skip; may repeat",
    )
    parser.add_argument(
        "--deny-re",
        action="append",
        default=[],
        help="additional deny regex; may repeat",
    )
    parser.add_argument(
        "--format",
        choices=["text", "json"],
        default="text",
        help="output format (default: text)",
    )
    return parser.parse_args(argv)


def load_config(path: pathlib.Path | None) -> dict[str, Any]:
    if path is None or not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"boundary-lint: invalid JSON in {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"boundary-lint: expected object at top-level in {path}")
    schema = data.get("schema")
    if schema not in (None, "worklog.boundary.v1"):
        raise SystemExit(f"boundary-lint: unsupported schema {schema!r} in {path}")
    return data


def normalize_deny(items: list[Any], cli_items: list[str]) -> list[DenyPattern]:
    patterns: list[DenyPattern] = []
    for item in items:
        if isinstance(item, str):
            patterns.append(DenyPattern(item))
            continue
        if isinstance(item, dict) and isinstance(item.get("pattern"), str):
            note = item.get("note", "")
            if note is not None and not isinstance(note, str):
                raise SystemExit("boundary-lint: deny[].note must be a string")
            patterns.append(DenyPattern(item["pattern"], note or ""))
            continue
        raise SystemExit("boundary-lint: deny entries must be strings or {pattern,note}")
    patterns.extend(DenyPattern(item) for item in cli_items)
    return patterns


def normalize_allow(items: list[Any]) -> list[AllowPattern]:
    patterns: list[AllowPattern] = []
    for item in items:
        if not isinstance(item, dict):
            raise SystemExit("boundary-lint: allow entries must be {path,pattern}")
        path = item.get("path")
        pattern = item.get("pattern")
        if not isinstance(path, str) or not isinstance(pattern, str):
            raise SystemExit("boundary-lint: allow entries must be {path,pattern}")
        patterns.append(AllowPattern(path, pattern))
    return patterns


def relpath(path: pathlib.Path, repo: pathlib.Path) -> str:
    return path.relative_to(repo).as_posix()


def iter_paths(repo: pathlib.Path, includes: list[str], excludes: list[str]) -> list[pathlib.Path]:
    seen: set[pathlib.Path] = set()
    paths: list[pathlib.Path] = []
    for pattern in includes:
        for raw in glob.glob(str(repo / pattern), recursive=True):
            path = pathlib.Path(raw)
            if not path.is_file() or path in seen:
                continue
            rel = relpath(path, repo)
            if any(fnmatch.fnmatch(rel, exclude) for exclude in excludes):
                continue
            seen.add(path)
            paths.append(path)
    return sorted(paths, key=lambda p: relpath(p, repo))


def compile_regex(pattern: str, ignore_case: bool) -> re.Pattern[str]:
    flags = re.IGNORECASE if ignore_case else 0
    try:
        return re.compile(pattern, flags)
    except re.error as exc:
        raise SystemExit(f"boundary-lint: invalid regex {pattern!r}: {exc}") from exc


def is_allowed(
    rel: str,
    text: str,
    compiled_allow: list[tuple[AllowPattern, re.Pattern[str]]],
) -> bool:
    for allow, regex in compiled_allow:
        if fnmatch.fnmatch(rel, allow.path) and regex.search(text):
            return True
    return False


def scan(
    repo: pathlib.Path,
    paths: list[pathlib.Path],
    deny: list[DenyPattern],
    allow: list[AllowPattern],
    ignore_case: bool,
) -> list[dict[str, Any]]:
    compiled_deny = [
        (item, compile_regex(item.pattern, ignore_case))
        for item in deny
    ]
    compiled_allow = [
        (item, compile_regex(item.pattern, ignore_case))
        for item in allow
    ]
    issues: list[dict[str, Any]] = []
    for path in paths:
        rel = relpath(path, repo)
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError as exc:
            raise SystemExit(f"boundary-lint: could not read {rel} as utf-8: {exc}") from exc
        for line_no, line in enumerate(lines, start=1):
            for item, regex in compiled_deny:
                if not regex.search(line):
                    continue
                if is_allowed(rel, line, compiled_allow):
                    continue
                issues.append(
                    {
                        "file": rel,
                        "line": line_no,
                        "pattern": item.pattern,
                        "note": item.note,
                        "text": line.strip(),
                    }
                )
    return issues


def emit_text(label: str, config_path: pathlib.Path | None, issues: list[dict[str, Any]]) -> None:
    source = f" ({config_path})" if config_path is not None and config_path.exists() else ""
    if not issues:
        print(f"boundary-lint: {label}: clean{source}")
        return
    print(f"boundary-lint: {label}: {len(issues)} violation(s){source}")
    for issue in issues:
        note = f" — {issue['note']}" if issue["note"] else ""
        print(
            f"{issue['file']}:{issue['line']}: "
            f"{issue['pattern']!r}{note}: {issue['text']}"
        )


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    repo = pathlib.Path(args.repo).expanduser().resolve()
    config_path = (
        pathlib.Path(args.config).expanduser().resolve()
        if args.config
        else repo / ".worklog-boundary.json"
    )
    config = load_config(config_path)

    include = list(config.get("include") or DEFAULT_INCLUDES)
    include.extend(args.include)
    exclude = list(config.get("exclude") or [])
    exclude.extend(args.exclude)
    deny = normalize_deny(list(config.get("deny") or []), args.deny_re)
    allow = normalize_allow(list(config.get("allow") or []))
    ignore_case = bool(config.get("ignore_case", True))
    label = str(config.get("label") or repo.name)

    if not deny:
        if args.format == "json":
            print(json.dumps({"label": label, "total": 0, "issues": [], "configured": False}))
        else:
            print(f"boundary-lint: {label}: no deny patterns configured")
        return 0

    paths = iter_paths(repo, include, exclude)
    issues = scan(repo, paths, deny, allow, ignore_case)
    if args.format == "json":
        print(
            json.dumps(
                {
                    "label": label,
                    "total": len(issues),
                    "issues": issues,
                    "configured": bool(config),
                    "files_scanned": len(paths),
                },
                sort_keys=True,
            )
        )
    else:
        emit_text(label, config_path, issues)
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
