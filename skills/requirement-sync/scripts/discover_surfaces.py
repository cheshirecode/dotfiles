#!/usr/bin/env python3
"""Scan a project for the surfaces a requirement can be written down in.

Read-only. Makes no network call and writes nothing. It proposes; the operator
decides, because a scan can see structure and cannot see intent.

    discover_surfaces.py [root] [--json]

Every surface is reported in one of four states, never collapsed:

    found     evidence in the tree, and the evidence is named
    absent    looked, and there is nothing
    unknown   cannot be decided by scanning -- a question is printed instead
    n/a       the kind does not apply here

`unknown` is the important one. A scanner that reports what it recognises and
stays silent about the rest teaches the operator that silence means absence,
which is the failure this whole skill is about.
"""
import argparse
import json
import os
import pathlib
import re
import subprocess
import sys

FRONTMATTER = re.compile(rb"\A---\s*\n(.{0,4096}?)\n---", re.S)
NEXT_ACTION = re.compile(rb"^\s*next[_-]?action\s*:", re.M | re.I)
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", "dist", "build"}
CODE_EXT = {".py": "Python", ".js": "JavaScript", ".ts": "TypeScript", ".sh": "shell",
            ".go": "Go", ".rb": "Ruby", ".rs": "Rust", ".java": "Java", ".sql": "SQL"}
# Test data and templates LOOK exactly like the surface they stand in for -- found
# by dogfooding, where this repo's own worklog fixtures reported as live working
# notes. They are classified rather than filtered: a filter would hide a real
# surface that happens to live under one of these names, so they are counted and
# named instead, and the operator decides.
NOT_LIVE = {"tests", "test", "fixtures", "fixture", "testdata", "templates", "template",
            "examples", "example"}


def partition(paths):
    live, staged = [], []
    for rel in paths:
        parts = set(pathlib.PurePath(rel).parts)
        (staged if parts & NOT_LIVE else live).append(rel)
    return live, staged


def walk(root, limit=4000):
    """Bounded walk. A scan that hangs on a huge tree gets killed and reports nothing."""
    seen = 0
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            seen += 1
            if seen > limit:
                return
            yield pathlib.Path(base) / name


def git(root, *args):
    p = subprocess.run(["git", "-C", str(root), *args],
                       capture_output=True, text=True, check=False)
    return p.stdout.strip() if p.returncode == 0 else None


def find_tracker(root):
    url = git(root, "remote", "get-url", "origin")
    if url is None:
        return dict(state="unknown", why="not a git repository, or no origin remote",
                    question="Which tracker holds work items for this project, and how do "
                             "you search its titles and bodies?")
    host = re.sub(r"^(?:https://|git@)([^/:]+).*", r"\1", url)
    # A forge is where the code lives. It is NOT evidence of where work is tracked:
    # plenty of projects host code in one place and issues in another.
    return dict(state="unknown", evidence=[f"origin is on {host}"],
                question=f"Work items: this project's code is on {host}. Is its tracker "
                         f"{host} issues, or something else? How do you search titles and "
                         f"bodies, and how do you read WHY a closed item was closed?")


def find_working_notes(root, files):
    hits = []
    for f in files:
        if f.suffix != ".md":
            continue
        try:
            with f.open("rb") as fh:
                head = fh.read(4096)
        except OSError:
            continue
        m = FRONTMATTER.match(head)
        if m and NEXT_ACTION.search(m.group(1)):
            hits.append(str(f.relative_to(root)))
    live, staged = partition(hits)
    if live:
        return dict(state="found", evidence=live[:5], count=len(live),
                    fixtures=len(staged),
                    note="markdown with a next-action field in frontmatter")
    ask = ("Do working notes for this project live outside the repository? "
           "If so, where, and how is one read?")
    if staged:
        return dict(state="absent", evidence=[f"{len(staged)} under test/template paths, "
                                              f"e.g. {staged[0]}"],
                    why="every match is test data or a template, not a live note",
                    question=ask)
    return dict(state="absent", why="no markdown carries a next-action frontmatter field",
                question=ask)


def find_published(root, files):
    html = [str(f.relative_to(root)) for f in files if f.suffix in (".html", ".htm")]
    live, staged = partition(html)
    if live:
        return dict(state="found", evidence=live[:5], count=len(live), fixtures=len(staged),
                    note="published pages are checked with the artifact-gate skill")
    if staged:
        return dict(state="absent", evidence=[f"{len(staged)} under test/template paths, "
                                              f"e.g. {staged[0]}"],
                    why="every match is test data or a template, not a published page",
                    question="Is anything published from this project as a page or "
                             "dashboard that restates facts from the code or the tracker?")
    return dict(state="absent", why="no HTML in the tree",
                question="Is anything published from this project as a page or dashboard "
                         "that restates facts from the code or the tracker?")


def find_memory(root, files):
    names = {"AGENTS.md", "CLAUDE.md", "CONVENTIONS.md", "CONTRIBUTING.md"}
    hits = [str(f.relative_to(root)) for f in files
            if f.name in names or "memory" in f.parts[:-1]]
    if hits:
        return dict(state="found", evidence=sorted(hits)[:5], count=len(hits),
                    note="durable rules that can rest on a fact that has since moved")
    return dict(state="absent", why="no convention or memory files found",
                question="Where are the standing rules for this project written down?")


def find_code(root, files):
    langs = {}
    for f in files:
        lang = CODE_EXT.get(f.suffix)
        if lang:
            langs[lang] = langs.get(lang, 0) + 1
    if langs:
        top = sorted(langs.items(), key=lambda kv: -kv[1])
        return dict(state="found", evidence=[f"{k} ({v})" for k, v in top[:4]],
                    note="grep comments asserting an invariant nothing tests")
    return dict(state="absent", why="no recognised source files")


def discover(root):
    root = pathlib.Path(root).resolve()
    files = list(walk(root))
    return {
        "root": str(root),
        "files_scanned": len(files),
        "surfaces": {
            "tracked item": find_tracker(root),
            "working note": find_working_notes(root, files),
            "published page": find_published(root, files),
            "durable memory": find_memory(root, files),
            "code comment": find_code(root, files),
        },
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--json", action="store_true", help="emit the declarations skeleton")
    args = ap.parse_args(argv)
    if not pathlib.Path(args.root).is_dir():
        print(f"discover_surfaces: not a directory: {args.root}", file=sys.stderr)
        return 2
    result = discover(args.root)
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0

    print(f"scanned {result['files_scanned']} file(s) under {result['root']}\n")
    questions = []
    for kind, info in result["surfaces"].items():
        detail = ", ".join(info.get("evidence", [])) or info.get("why", "")
        print(f"  {info['state']:<8} {kind:<16} {detail[:88]}")
        if info.get("question"):
            questions.append((kind, info["question"]))
    if questions:
        print("\nAsk before declaring these. A scan sees structure, not intent:")
        for kind, q in questions:
            print(f"\n  [{kind}]\n  {q}")
    print("\nNothing was written. Record the answers as the declarations in step 0.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
