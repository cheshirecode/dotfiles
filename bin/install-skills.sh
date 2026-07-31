#!/usr/bin/env bash
# Install agent skills from manifest/skills.yaml into all supported user roots:
# ~/.claude/skills/ for Claude Code, ~/.agents/skills/ for Codex and shared
# discovery, and ~/.cursor/skills/ for Cursor's native discovery surface.
#
# Two source types:
#   - subpath:  copy a directory from this repo (vendored skill).
#   - git:      clone a repo at a pinned SHA, then symlink (Mac/Linux) or
#               copy (WSL fallback) into all three user skill roots.
#
# Mac/Linux uses symlinks (cheap, easy upgrade). WSL2 inherits Linux behavior.
# Windows-native is unsupported — install.sh refuses earlier.
#
# Idempotent. Re-running upgrades to the manifest's current SHA.
#
# Usage:
#   bin/install-skills.sh            # install all skills in manifest
#   bin/install-skills.sh --dry-run  # print actions, don't apply
#   bin/install-skills.sh <name>     # install a single skill

set -euo pipefail

DRY_RUN=0
SINGLE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      cat <<EOF
usage: install-skills.sh [--dry-run] [<name>]
  --dry-run   print intended actions, don't apply.
  <name>      install only this skill (else: install all from manifest).
EOF
      exit 0
      ;;
    -*) echo "install-skills: unknown flag $1" >&2; exit 2 ;;
    *)  SINGLE="$1" ;;
  esac
  shift
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/manifest/skills.yaml"
[[ -f "$MANIFEST" ]] || { echo "install-skills: manifest not found at $MANIFEST" >&2; exit 1; }

SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
SHARED_SKILLS_DIR="${AGENT_SKILLS_DIR:-$HOME/.agents/skills}"
CURSOR_SKILLS_DIR="${CURSOR_SKILLS_DIR:-$HOME/.cursor/skills}"
SOURCE_CACHE_DIR="${CLAUDE_AGENT_CACHE:-$HOME/.cache/dotfiles-agent-skills}"

if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$SKILLS_DIR" "$SHARED_SKILLS_DIR" "$CURSOR_SKILLS_DIR" "$SOURCE_CACHE_DIR"
fi

# Parse manifest via Python (yaml is stdlib-adjacent; safer than awk on YAML).
python3 - "$MANIFEST" "$SINGLE" "$DRY_RUN" "$SKILLS_DIR" "$SHARED_SKILLS_DIR" "$CURSOR_SKILLS_DIR" "$SOURCE_CACHE_DIR" "$REPO_ROOT" <<'PY'
import os, sys, shutil, subprocess, pathlib
try:
    import yaml
except ImportError:
    sys.stderr.write("install-skills: PyYAML not installed. Run: pip3 install --user pyyaml\n")
    sys.exit(1)

manifest_path, single, dry_run, skills_dir, shared_skills_dir, cursor_skills_dir, source_cache_dir, repo_root = sys.argv[1:9]
dry = dry_run == "1"
skills_dir = pathlib.Path(skills_dir).expanduser()
shared_skills_dir = pathlib.Path(shared_skills_dir).expanduser()
cursor_skills_dir = pathlib.Path(cursor_skills_dir).expanduser()
source_cache_dir = pathlib.Path(source_cache_dir).expanduser()
repo_root = pathlib.Path(repo_root)

m = yaml.safe_load(open(manifest_path))
entries = m["skills"]
if single:
    entries = [e for e in entries if e["name"] == single]
    if not entries:
        sys.stderr.write(f"install-skills: no manifest entry for '{single}'\n")
        sys.exit(2)

def run(cmd, check=True):
    if dry:
        print(f"  [dry-run] {' '.join(cmd)}")
        return
    subprocess.run(cmd, check=check)

SENTINEL = ".installed_from"
import re as _re
import hashlib as _hashlib

def tree_digest(root):
    digest = _hashlib.sha256()
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        relative_path = path.relative_to(root).as_posix()
        if relative_path == SENTINEL:
            continue
        relative = relative_path.encode()
        if path.is_symlink():
            digest.update(b"L\0" + relative + b"\0" + os.readlink(path).encode() + b"\0")
        elif path.is_file():
            digest.update(b"F\0" + relative + b"\0")
            digest.update(_hashlib.sha256(path.read_bytes()).digest())
        elif path.is_dir():
            digest.update(b"D\0" + relative + b"\0")
    return digest.hexdigest()

def validate_frontmatter(skill_dir, expected_name):
    """Council item #3: validate SKILL.md frontmatter at install time, not at
    diagnostic time. Returns None on success, error string on failure."""
    skill_md = pathlib.Path(skill_dir) / "SKILL.md"
    if not skill_md.is_file():
        return f"missing SKILL.md at {skill_md}"
    text = skill_md.read_text()
    m = _re.match(r'^---\s*\n(.*?)\n---', text, _re.DOTALL)
    if not m:
        return f"{skill_md}: no YAML frontmatter (must start with ---)"
    block = m.group(1)
    nm = _re.search(r'^name:\s*(\S+)', block, _re.MULTILINE)
    if not nm:
        return f"{skill_md}: frontmatter missing 'name:' field"
    actual = nm.group(1).strip('"\'')
    if actual != expected_name:
        return f"{skill_md}: frontmatter name='{actual}' but manifest says '{expected_name}'"
    return None

def has_our_sentinel(dst, src, source_info):
    """True if dst is one of ours (safe to replace).

    A symlink is ours only when it resolves to the current source. Any other
    symlink may be a user-owned link and must remain fail-closed. Copies carry
    a content digest so local edits are not mistaken for installer state.
    """
    if dst.is_symlink():
        try:
            return dst.resolve(strict=True) == src.resolve(strict=True)
        except FileNotFoundError:
            return False
    sentinel = dst / SENTINEL
    if not sentinel.is_file():
        return False
    try:
        lines = sentinel.read_text().splitlines()
    except OSError:
        return False
    if not lines or lines[0] != source_info:
        return False
    digest_lines = [line for line in lines[1:] if line.startswith("content-sha256:")]
    if digest_lines:
        return digest_lines[-1].split(":", 1)[1] == tree_digest(dst)
    # Legacy sentinels remain safe only when the installed copy still matches
    # the current source exactly; otherwise ownership is ambiguous.
    return tree_digest(dst) == tree_digest(src)

def refuse_if_unowned(dst, name, src, source_info):
    """Council guardrail #8: never rmtree a user-edited skill dir.
    If dst exists and we don't recognize it as ours, check if it's a
    byte-identical copy. If identical, allow replacement. If divergent, refuse."""
    if (dst.is_symlink() or dst.exists()) and not has_our_sentinel(dst, src, source_info):
        if dst.is_dir() and not dst.is_symlink():
            if src and src.is_dir() and tree_digest(dst) == tree_digest(src):
                return
        ownership_reason = (
            f"its symlink target does not match the current source {src}"
            if dst.is_symlink()
            else (
                f"it has no '{SENTINEL}' sentinel"
                if not (dst / SENTINEL).is_file()
                else f"its '{SENTINEL}' content does not match the installed copy"
            )
        )
        sys.stderr.write(
            f"install-skills: refusing to replace {dst}\n"
            f"  '{name}' is unowned because {ownership_reason}.\n"
            f"  It may contain local edits or use an older ownership format.\n"
            f"  Inspect it and remove it manually if safe,\n"
            f"  then re-run install-skills.sh.\n"
        )
        sys.exit(3)

def write_sentinel(dst, source_info, src):
    """Write a sentinel so future install-skills runs recognize this dir."""
    (dst / SENTINEL).write_text(
        f"{source_info}\ncontent-sha256:{tree_digest(src)}\n"
    )

def install_destinations(entry):
    """Preserve the manifest destination and add shared and Cursor roots."""
    destinations = [
        pathlib.Path(entry["install_to"]).expanduser(),
        shared_skills_dir / entry["name"],
        cursor_skills_dir / entry["name"],
    ]
    return list(dict.fromkeys(destinations))

def link_or_copy(src, dst, name, source_info):
    if dst.is_symlink() or dst.exists():
        print(f"  refresh {name}: {dst}")
        if not dry:
            if dst.is_symlink(): dst.unlink()
            elif dst.is_dir():    shutil.rmtree(dst)
            else:                  dst.unlink()
    else:
        print(f"  install {name}: {dst}")
    if not dry:
        dst.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.symlink(src.resolve(), dst)
        except OSError:
            shutil.copytree(src, dst)
            write_sentinel(dst, source_info, src)

def install_subpath(entry):
    src = repo_root / entry["source"]["path"]
    if not src.exists():
        if entry.get("optional") is True:
            print(f"  SKIP optional {entry['name']}: source {src} not present")
            return False
        sys.stderr.write(
            f"install-skills: refusing {entry['name']}: source {src} not present\n"
            f"  Required subpath skills must exist in this repo. Add optional: true\n"
            f"  only if the absence is intentional.\n"
        )
        sys.exit(3)
    # Council item #3: validate source frontmatter BEFORE install. Prevents a
    # malformed SKILL.md from being symlinked into ~/.claude/skills/.
    err = validate_frontmatter(src, entry["name"])
    if err:
        sys.stderr.write(f"install-skills: refusing {entry['name']}: {err}\n")
        sys.exit(3)
    source_info = f"subpath:{entry['source']['path']}"
    destinations = install_destinations(entry)
    for dst in destinations:
        refuse_if_unowned(dst, entry["name"], src, source_info)
    for dst in destinations:
        link_or_copy(
            src,
            dst,
            entry["name"],
            source_info,
        )
    return True

def install_git(entry):
    import re as _re
    name = entry["name"]
    repo = entry["source"]["repo"]
    ref = entry["source"]["ref"]
    # Council guardrail #7: refuse non-SHA refs for git-source entries.
    # "SHA pinning IS the integrity check" — ref:HEAD or branch names defeat it.
    if not _re.fullmatch(r"[0-9a-f]{40}", ref) and not os.environ.get("INSTALL_SKILLS_ALLOW_MOVING_REF"):
        sys.stderr.write(
            f"install-skills: refusing {name}: source.ref='{ref}' is not a 40-hex SHA.\n"
            f"  type:git entries must SHA-pin so content swaps aren't invisible.\n"
            f"  Override with INSTALL_SKILLS_ALLOW_MOVING_REF=1 if you really mean it.\n"
        )
        sys.exit(3)
    cache = source_cache_dir / name
    # Council guardrail #10: atomic clone-or-swap on git operations.
    # Mid-fetch network failure must not leave the cache dir in a half-state.
    import tempfile as _tempfile
    if not cache.exists():
        # First-time clone: clone into staging, then rename. If clone fails,
        # there's no half-populated cache dir to confuse the next run.
        print(f"  clone {name}: {repo} → {cache}")
        if not dry:
            staging = pathlib.Path(_tempfile.mkdtemp(prefix=f".{name}-staging-", dir=source_cache_dir))
            shutil.rmtree(staging)  # mkdtemp made it; git clone wants it absent
            try:
                run(["git", "clone", "--quiet", f"https://github.com/{repo}.git", str(staging)])
                run(["git", "-C", str(staging), "checkout", "--quiet", ref])
                staging.rename(cache)
            except Exception:
                shutil.rmtree(staging, ignore_errors=True)
                raise
        else:
            run(["git", "clone", "--quiet", f"https://github.com/{repo}.git", str(cache)])
            run(["git", "-C", str(cache), "checkout", "--quiet", ref])
    else:
        # Upgrade path: fetch + checkout in place; on failure, the prior
        # checkout remains usable (git is internally atomic for these ops).
        print(f"  upgrade {name}: {cache} → {ref[:12]}")
        run(["git", "-C", str(cache), "fetch", "--quiet", "origin"])
        run(["git", "-C", str(cache), "checkout", "--quiet", ref])
    source_info = f"git:{repo}@{ref}"
    destinations = install_destinations(entry)
    for dst in destinations:
        refuse_if_unowned(dst, name, cache, source_info)
    for dst in destinations:
        link_or_copy(cache, dst, name, source_info)
    return True

installed = skipped = 0
for entry in entries:
    src_type = entry["source"]["type"]
    if src_type == "subpath":
        if install_subpath(entry): installed += 1
        else: skipped += 1
    elif src_type == "git":
        if install_git(entry): installed += 1
        else: skipped += 1
    else:
        print(f"  SKIP {entry['name']}: unknown source.type={src_type}")
        skipped += 1

print(f"install-skills: {installed} installed, {skipped} skipped ({'dry-run' if dry else 'applied'})")
PY
