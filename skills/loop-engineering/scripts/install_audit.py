#!/usr/bin/env python3
"""Audit and safely consolidate loop-engineering skill installations."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import uuid


CLEAN_STATUSES = {"absent", "linked", "source"}
DIVERGENT_STATUSES = {
    "broken-symlink",
    "divergent-copy",
    "divergent-symlink",
    "unsupported",
}


def digest_ignored(path: pathlib.Path, root: pathlib.Path) -> bool:
    # Bytecode caches are interpreter- and machine-local: running the skill's
    # own test suite creates them, and counting them would make a byte-identical
    # source install read as divergent-copy forever (observed live 2026-08-31).
    relative_parts = path.relative_to(root).parts
    return "__pycache__" in relative_parts or path.suffix == ".pyc"


def tree_digest(root: pathlib.Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        if digest_ignored(path, root):
            continue
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


def git_output(directory: pathlib.Path, *arguments: str) -> str | None:
    """Read-only git call; None when git is missing or the command fails."""
    try:
        result = subprocess.run(
            ["git", "-C", str(directory), *arguments],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def repo_head(directory: pathlib.Path) -> tuple[pathlib.Path, str] | None:
    top = git_output(directory, "rev-parse", "--show-toplevel")
    if not top:
        return None
    head = git_output(directory, "rev-parse", "HEAD")
    if not head:
        return None
    return pathlib.Path(top), head


def commit_relation(
    repositories: list[pathlib.Path],
    mine: str,
    theirs: str,
) -> str:
    """Where `mine` sits relative to `theirs`, judged in a repo holding both.

    A stale clone has never fetched the newer commit, so the comparison has to
    run in whichever clone actually has both objects — usually the other one.
    """
    if mine == theirs:
        return "same-commit"
    for repository in repositories:
        if any(
            git_output(repository, "cat-file", "-e", f"{commit}^{{commit}}") is None
            for commit in (mine, theirs)
        ):
            continue
        behind = git_output(repository, "rev-list", "--count", f"{mine}..{theirs}")
        ahead = git_output(repository, "rev-list", "--count", f"{theirs}..{mine}")
        if behind is None or ahead is None:
            continue
        if ahead == "0":
            return f"behind:{behind}"
        if behind == "0":
            return f"ahead:{ahead}"
        return f"diverged:{ahead}+{behind}"
    return "unknown"


def remote_commit(repository: pathlib.Path) -> str | None:
    """The tracked remote tip *as of the last fetch* — this never goes online."""
    upstream = git_output(
        repository, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"
    )
    candidates = [upstream] if upstream else []
    candidates.extend(("origin/HEAD", "origin/main", "origin/master"))
    for candidate in candidates:
        commit = git_output(repository, "rev-parse", "--verify", "--quiet", candidate)
        if commit:
            return commit
    return None


def drift_fields(
    root: pathlib.Path,
    canonical_repository: pathlib.Path | None,
    canonical_commit: str | None,
) -> dict[str, str]:
    """Commit-level drift for the clone this root actually loads from.

    Content comparison cannot see this: a symlink into a clone five commits
    behind is byte-identical to that clone and reads `linked`, while the skill
    text a session loads disagrees with the clone being edited.
    """
    try:
        resolved = root.resolve(strict=True)
    except (FileNotFoundError, RuntimeError):
        return {}
    if not resolved.is_dir():
        return {}
    installed = repo_head(resolved)
    if installed is None:
        return {"source_drift": "no-git", "remote_drift": "no-git"}
    repository, head = installed
    fields = {"commit": head[:12]}
    if canonical_repository is None or canonical_commit is None:
        fields["source_drift"] = "no-git"
    else:
        fields["source_drift"] = commit_relation(
            [canonical_repository, repository], head, canonical_commit
        )
    tracked = remote_commit(repository)
    fields["remote_drift"] = (
        "no-remote" if tracked is None else commit_relation([repository], head, tracked)
    )
    return fields


def is_stale(entry: dict[str, str]) -> bool:
    return any(
        entry.get(field, "").startswith(("behind", "diverged"))
        for field in ("source_drift", "remote_drift")
    )


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
        if is_stale(entry):
            suffix += (
                f" [source {entry['source_drift']}, remote {entry['remote_drift']}]"
            )
        print(f"{entry['status']}: {entry['path']}{suffix}")


def main() -> int:
    args = build_parser().parse_args()
    try:
        canonical = args.canonical.expanduser().resolve(strict=True)
    except FileNotFoundError:
        print(
            f"install-audit: canonical path does not exist: {args.canonical}",
            file=sys.stderr,
        )
        return 2
    if not (canonical / "SKILL.md").is_file():
        print(
            f"install-audit: canonical skill is missing SKILL.md: {canonical}",
            file=sys.stderr,
        )
        return 2

    raw_roots = args.root or default_roots(pathlib.Path.home())
    # Normalize the parent (so `..` spellings match) but keep the leaf as
    # given: resolving the leaf itself would follow an installed symlink and
    # misclassify `linked` roots. Dedupe — symlinked roots can alias one
    # install, and repairing the same install twice rmtree's a symlink.
    roots: list[pathlib.Path] = []
    seen: set[pathlib.Path] = set()
    for root in raw_roots:
        root = root.expanduser().absolute()
        normalized = root.parent.resolve(strict=False) / root.name
        if normalized in seen:
            continue
        seen.add(normalized)
        roots.append(normalized)
    canonical_digest = tree_digest(canonical)
    canonical_repository, canonical_commit = repo_head(canonical) or (None, None)

    def audit(root: pathlib.Path) -> dict[str, str]:
        entry = classify(root, canonical, canonical_digest)
        return entry | drift_fields(root, canonical_repository, canonical_commit)

    entries = [audit(root) for root in roots]

    write_failures = 0
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
                try:
                    replace_identical_copy(root, canonical)
                except OSError as exc:
                    write_failures += 1
                    print(
                        f"install-audit: failed to link {root}: {exc}",
                        file=sys.stderr,
                    )
        entries = [audit(root) for root in roots]

    render(entries, args.json)
    stale = [entry for entry in entries if is_stale(entry)]
    for entry in stale:
        print(
            f"install-audit: stale install: {entry['path']} "
            f"(source {entry['source_drift']}, remote {entry['remote_drift']}) "
            "- the clone this root loads from is behind; pull it",
            file=sys.stderr,
        )
    if write_failures or stale:
        return 1
    return 0 if all(entry["status"] in CLEAN_STATUSES for entry in entries) else 1


if __name__ == "__main__":
    raise SystemExit(main())
