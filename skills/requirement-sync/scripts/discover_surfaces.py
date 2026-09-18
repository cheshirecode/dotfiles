#!/usr/bin/env python3
"""Scan projects for the surfaces a requirement can be written down in.

Read-only. Makes no network call and writes nothing. It proposes; the operator
decides, because a scan sees structure and cannot see intent.

    discover_surfaces.py [root ...] [--json]

Each kind of surface is reported in one of four states, never collapsed:

    found     evidence under a scanned root, named, shallowest path first
    absent    looked at EVERYTHING under the scanned roots and found none --
              which still is not "does not exist", because a project's notes,
              ledger and memory store routinely live in another repository or
              off-disk entirely. Every absent carries the question that asks
              where else to look. Pass more roots and scan again.
    unknown   cannot be decided here -- a question is printed instead
    n/a       the kind does not apply

`absent` is only ever claimed from a complete walk. If inspection had to stop
early the state degrades to `unknown`, because an absence claim from a sample
is not a measurement: on one real tree an earlier version read 4,000 of 109,475
files, 3.7%, and reported two surfaces absent off that sample.
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
# Directories whose contents are duplicates or vendored, skipped before counting.
# A worktree is a second checkout of the same repository, so every file in it
# already exists at the root and is usually staler; on one real tree 79% of all
# files were worktree copies, and the memory surface cited a detached one while
# the canonical file sat at the root.
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", "dist", "build",
             "worktrees", ".worktrees", "site-packages", ".tox", ".mypy_cache"}
# Not duplicates -- they are real files that merely look like a live surface.
# Classified and counted rather than filtered, so a genuine surface sitting under
# one of these names is still reported.
NOT_LIVE = {"tests", "test", "fixtures", "fixture", "testdata", "templates",
            "template", "examples", "example"}
CODE_EXT = {".py": "Python", ".js": "JavaScript", ".ts": "TypeScript", ".sh": "shell",
            ".go": "Go", ".rb": "Ruby", ".rs": "Rust", ".java": "Java", ".sql": "SQL"}
READ_CAP = 3000  # frontmatter reads, the only expensive step


def walk(root):
    """Every path under root, minus duplicate and vendored directories.

    Listing is cheap; only reading file contents is not. So the walk is complete
    and the cap is applied to reads alone, which keeps the extension-based
    surfaces free of any truncation at all.
    """
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            yield pathlib.Path(base) / name


def partition(paths):
    live, staged = [], []
    for rel in paths:
        parts = set(pathlib.PurePath(rel).parts)
        (staged if parts & NOT_LIVE else live).append(rel)
    return live, staged


def shallowest(paths, limit=5):
    """Cite the canonical copy: the shallowest path, not whichever came first."""
    return sorted(paths, key=lambda p: (len(pathlib.PurePath(p).parts), p))[:limit]


def git(root, *args):
    p = subprocess.run(["git", "-C", str(root), *args],
                       capture_output=True, text=True, check=False)
    return p.stdout.strip() if p.returncode == 0 else None


def find_tracker(roots):
    hosts = []
    for r in roots:
        url = git(r, "remote", "get-url", "origin")
        if url:
            hosts.append(re.sub(r"^(?:https://|git@)([^/:]+).*", r"\1", url))
    if not hosts:
        return dict(state="unknown", why="no git remote under any scanned root",
                    question="Which tracker holds work items for this project? How do you "
                             "search its titles and bodies, and how do you read WHY a "
                             "closed item was closed?")
    # A forge is where the code lives. It is NOT evidence of where work is
    # tracked: a project routinely hosts code in one place and issues in another.
    seen = sorted(set(hosts))
    return dict(state="unknown", evidence=[f"origin is on {h}" for h in seen],
                question=f"Work items: code is on {', '.join(seen)}. Is the tracker there, "
                         f"or somewhere else entirely? How do you search titles and bodies, "
                         f"and how do you read WHY a closed item was closed?")


def find_working_notes(files):
    hits, read, truncated = [], 0, False
    for rel, path in files:
        if path.suffix != ".md":
            continue
        if read >= READ_CAP:
            truncated = True
            break
        read += 1
        try:
            with path.open("rb") as fh:
                head = fh.read(4096)
        except OSError:
            continue
        m = FRONTMATTER.match(head)
        if m and NEXT_ACTION.search(m.group(1)):
            hits.append(rel)
    live, staged = partition(hits)
    ask = ("Do working notes for this project live outside these roots — another "
           "repository, a vault, a document store? Where, and how is one read?")
    if live:
        return dict(state="found", evidence=shallowest(live), count=len(live),
                    fixtures=len(staged), question=ask,
                    note="markdown with a next-action field in frontmatter")
    if truncated:
        return dict(state="unknown", why=f"stopped after reading {read} markdown files; "
                                         f"absence cannot be claimed from a sample",
                    question=ask)
    if staged:
        return dict(state="absent", evidence=[f"{len(staged)} under test or template "
                                              f"paths, e.g. {staged[0]}"],
                    why="every match is test data or a template", question=ask)
    return dict(state="absent", why="no markdown under these roots carries a next-action "
                                    "frontmatter field", question=ask)


def find_published(files):
    html = [rel for rel, p in files if p.suffix in (".html", ".htm")]
    live, staged = partition(html)
    # "No HTML here" is evidence about these roots. It is not evidence about
    # whether anything is published: a published page usually lives on a host,
    # not in a repository. So the question is asked either way.
    ask = ("Is anything published from this project — a page, dashboard or ledger, "
           "in a repo or on a host — that restates facts from the code or tracker?")
    if live:
        return dict(state="found", evidence=shallowest(live), count=len(live),
                    fixtures=len(staged), question=ask,
                    note="published pages are checked with the artifact-gate skill")
    if staged:
        return dict(state="absent", evidence=[f"{len(staged)} under test or template "
                                              f"paths, e.g. {staged[0]}"],
                    why="every match is test data or a template", question=ask)
    return dict(state="absent", why="no HTML under these roots; says nothing about pages "
                                    "published elsewhere", question=ask)


def find_memory(files):
    names = {"AGENTS.md", "CLAUDE.md", "CONVENTIONS.md", "CONTRIBUTING.md"}
    hits = [rel for rel, p in files
            if p.name in names or "memory" in pathlib.PurePath(rel).parts[:-1]]
    live, staged = partition(hits)
    ask = ("Where are the standing rules for this project written down, including any "
           "agent memory store outside the repository?")
    if live:
        return dict(state="found", evidence=shallowest(live), count=len(live),
                    fixtures=len(staged), question=ask,
                    note="durable rules that can rest on a fact that has since moved")
    if staged:
        return dict(state="absent", evidence=[f"{len(staged)} under template paths, "
                                              f"e.g. {staged[0]}"],
                    why="every match is a template", question=ask)
    return dict(state="absent", why="no convention or memory files under these roots",
                question=ask)


def find_code(files):
    langs = {}
    for _rel, p in files:
        lang = CODE_EXT.get(p.suffix)
        if lang:
            langs[lang] = langs.get(lang, 0) + 1
    if langs:
        top = sorted(langs.items(), key=lambda kv: -kv[1])
        return dict(state="found", evidence=[f"{k} ({v})" for k, v in top[:4]],
                    note="grep comments asserting an invariant nothing tests")
    return dict(state="absent", why="no recognised source files under these roots")


def discover(*roots):
    """Scan one or more roots. A repository is rarely the whole picture: the
    tracker is elsewhere by definition, and the notes, ledger and memory store
    often are too. Reporting `absent` from one root states a conclusion about
    places that were never looked at."""
    paths = [pathlib.Path(r).resolve() for r in (roots or ["."])]
    files = []
    for root in paths:
        for f in walk(root):
            try:
                files.append((str(f.relative_to(root)), f))
            except ValueError:
                files.append((str(f), f))
    return {
        "roots": [str(r) for r in paths],
        "files_scanned": len(files),
        "surfaces": {
            "tracked item": find_tracker(paths),
            "working note": find_working_notes(files),
            "published page": find_published(files),
            "durable memory": find_memory(files),
            "code comment": find_code(files),
        },
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("roots", nargs="*", default=["."], metavar="root")
    ap.add_argument("--json", action="store_true", help="emit the declarations skeleton")
    args = ap.parse_args(argv)
    for r in args.roots:
        if not pathlib.Path(r).is_dir():
            print(f"discover_surfaces: not a directory: {r}", file=sys.stderr)
            return 2
    result = discover(*args.roots)
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0

    print(f"scanned {result['files_scanned']} file(s) under "
          f"{', '.join(result['roots'])}\n")
    questions = []
    for kind, info in result["surfaces"].items():
        detail = ", ".join(info.get("evidence", [])) or info.get("why", "")
        print(f"  {info['state']:<8} {kind:<16} {detail[:88]}")
        if info.get("question"):
            questions.append((kind, info["question"]))
    if questions:
        print("\nAnswer these before declaring. A scan sees structure, not intent,\n"
              "and `absent` means not under the roots scanned — not that it does not exist:")
        for kind, q in questions:
            print(f"\n  [{kind}]\n  {q}")
    print("\nNothing was written. Record the answers as the declarations in step 0.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
