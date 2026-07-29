#!/usr/bin/env python3
"""Audit and safely consolidate loop-engineering skill installations."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import sys
import uuid


CLEAN_STATUSES = {"absent", "linked", "source"}
DIVERGENT_STATUSES = {
    "broken-symlink",
    "divergent-copy",
    "divergent-symlink",
    "unsupported",
}


def tree_digest(root: pathlib.Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        relative = path.relative_to(root).as_posix().encode()
        if path.is_symlink():
            digest.update(
                b"L\0" + relative + b"\0" + os.readlink(path).encode() + b"\0"
            )
        elif path.is_file():
            digest.update(b"F\0" + relative + b"\0")
            digest.update(hashlib.sha256(path.read_bytes()).digest())
        elif path.is_dir():
            digest.update(b"D\0" + relative + b"\0")
    return digest.hexdigest()


def same_path(left: pathlib.Path, right: pathlib.Path) -> bool:
    try:
        return left.resolve(strict=True) == right.resolve(strict=True)
    except FileNotFoundError:
        return False


def classify(
    root: pathlib.Path,
    canonical: pathlib.Path,
    canonical_digest: str,
) -> dict[str, str]:
    result = {"path": str(root)}
    if root.is_symlink():
        try:
            resolved = root.resolve(strict=True)
        except FileNotFoundError:
            return result | {"status": "broken-symlink", "target": os.readlink(root)}
        status = "linked" if same_path(resolved, canonical) else "divergent-symlink"
        return result | {"status": status, "target": str(resolved)}
    if not root.exists():
        return result | {"status": "absent"}
    if not root.is_dir():
        return result | {"status": "unsupported"}
    if same_path(root, canonical):
        return result | {"status": "source", "digest": canonical_digest}
    digest = tree_digest(root)
    status = "duplicate-identical" if digest == canonical_digest else "divergent-copy"
    return result | {"status": status, "digest": digest}


def replace_identical_copy(root: pathlib.Path, canonical: pathlib.Path) -> None:
    token = uuid.uuid4().hex
    backup = root.with_name(f"{root.name}.backup-{token}")
    temporary_link = root.with_name(f"{root.name}.link-{token}")
    os.symlink(f"{canonical}{os.sep}", temporary_link, target_is_directory=True)
    root.rename(backup)
    try:
        os.replace(temporary_link, root)
    except Exception:
        backup.rename(root)
        temporary_link.unlink(missing_ok=True)
        raise
    shutil.rmtree(backup)


def default_roots(home: pathlib.Path) -> list[pathlib.Path]:
    return [
        home / ".codex/skills/loop-engineering",
        home / ".agents/skills/loop-engineering",
        home / ".claude/skills/loop-engineering",
        home / ".cursor/skills/loop-engineering",
    ]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Audit loop-engineering installations against one canonical source."
    )
    parser.add_argument(
        "--canonical",
        type=pathlib.Path,
        default=pathlib.Path(__file__).parents[1],
        help="canonical loop-engineering directory (defaults to this script's skill)",
    )
    parser.add_argument(
        "--root",
        action="append",
        type=pathlib.Path,
        help="installation root to audit; repeat to override the four user defaults",
    )
    parser.add_argument(
        "--link-identical",
        action="store_true",
        help="replace byte-identical copied directories with canonical symlinks",
    )
    parser.add_argument("--json", action="store_true", help="emit JSON")
    return parser


def render(entries: list[dict[str, str]], as_json: bool) -> None:
    if as_json:
        print(json.dumps(entries, indent=2, sort_keys=True))
        return
    for entry in entries:
        detail = entry.get("target") or entry.get("digest", "")
        suffix = f" ({detail})" if detail else ""
        print(f"{entry['status']}: {entry['path']}{suffix}")


def main() -> int:
    args = build_parser().parse_args()
    canonical = args.canonical.expanduser().resolve(strict=True)
    if not (canonical / "SKILL.md").is_file():
        print(
            f"install-audit: canonical skill is missing SKILL.md: {canonical}",
            file=sys.stderr,
        )
        return 2

    roots = args.root or default_roots(pathlib.Path.home())
    roots = [root.expanduser().absolute() for root in roots]
    canonical_digest = tree_digest(canonical)
    entries = [classify(root, canonical, canonical_digest) for root in roots]

    if args.link_identical:
        if any(entry["status"] in DIVERGENT_STATUSES for entry in entries):
            render(entries, args.json)
            print(
                "install-audit: refusing all writes while a divergent installation exists",
                file=sys.stderr,
            )
            return 1
        for root, entry in zip(roots, entries):
            if entry["status"] == "duplicate-identical":
                replace_identical_copy(root, canonical)
        entries = [classify(root, canonical, canonical_digest) for root in roots]

    render(entries, args.json)
    return 0 if all(entry["status"] in CLEAN_STATUSES for entry in entries) else 1


if __name__ == "__main__":
    raise SystemExit(main())
