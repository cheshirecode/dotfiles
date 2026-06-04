#!/usr/bin/env bash
# Install agent skills from manifest/skills.yaml into ~/.claude/skills/.
#
# Two source types:
#   - subpath:  copy a directory from this repo (vendored skill).
#   - git:      clone a repo at a pinned SHA, then symlink (Mac/Linux) or
#               copy (WSL fallback) into ~/.claude/skills/<name>/.
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
CACHE_DIR="${CLAUDE_AGENT_CACHE:-$HOME/.agents/skills}"

mkdir -p "$SKILLS_DIR" "$CACHE_DIR"

# Parse manifest via Python (yaml is stdlib-adjacent; safer than awk on YAML).
python3 - "$MANIFEST" "$SINGLE" "$DRY_RUN" "$SKILLS_DIR" "$CACHE_DIR" "$REPO_ROOT" <<'PY'
import os, sys, shutil, subprocess, pathlib
try:
    import yaml
except ImportError:
    sys.stderr.write("install-skills: PyYAML not installed. Run: pip3 install --user pyyaml\n")
    sys.exit(1)

manifest_path, single, dry_run, skills_dir, cache_dir, repo_root = sys.argv[1:7]
dry = dry_run == "1"
skills_dir = pathlib.Path(skills_dir).expanduser()
cache_dir = pathlib.Path(cache_dir).expanduser()
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

def has_our_sentinel(dst):
    """True if dst is one of ours (safe to replace). Either a symlink we
    created (Mac/Linux happy path) or a copy with our sentinel file."""
    if dst.is_symlink():
        return True
    sentinel = dst / SENTINEL
    return sentinel.is_file()

def refuse_if_unowned(dst, name):
    """Council guardrail #8: never rmtree a user-edited skill dir.
    If dst exists and we don't recognize it as ours, refuse + prompt."""
    if (dst.is_symlink() or dst.exists()) and not has_our_sentinel(dst):
        sys.stderr.write(
            f"install-skills: refusing to replace {dst}\n"
            f"  '{name}' has a directory there but no '{SENTINEL}' sentinel.\n"
            f"  Either we didn't install it, or a previous install predates the\n"
            f"  sentinel. To proceed: rm -rf {dst} (you'll lose any local edits),\n"
            f"  then re-run install-skills.sh.\n"
        )
        sys.exit(3)

def write_sentinel(dst, source_info):
    """Write a sentinel so future install-skills runs recognize this dir."""
    (dst / SENTINEL).write_text(source_info + "\n")

def install_subpath(entry):
    src = repo_root / entry["source"]["path"]
    dst = pathlib.Path(entry["install_to"]).expanduser()
    if not src.exists():
        print(f"  SKIP {entry['name']}: source {src} not present (skill not vendored yet)")
        return False
    refuse_if_unowned(dst, entry["name"])
    if dst.is_symlink() or dst.exists():
        print(f"  refresh {entry['name']}: {dst}")
        if not dry:
            if dst.is_symlink(): dst.unlink()
            elif dst.is_dir():    shutil.rmtree(dst)
            else:                  dst.unlink()
    else:
        print(f"  install {entry['name']}: {dst}")
    if not dry:
        dst.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.symlink(src.resolve(), dst)
        except OSError:
            # WSL or filesystems without symlink support — fall back to copy.
            shutil.copytree(src, dst)
            write_sentinel(dst, f"subpath:{entry['source']['path']}")
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
    cache = cache_dir / name
    # Council guardrail #10: atomic clone-or-swap on git operations.
    # Mid-fetch network failure must not leave the cache dir in a half-state.
    import tempfile as _tempfile
    if not cache.exists():
        # First-time clone: clone into staging, then rename. If clone fails,
        # there's no half-populated cache dir to confuse the next run.
        print(f"  clone {name}: {repo} → {cache}")
        if not dry:
            staging = pathlib.Path(_tempfile.mkdtemp(prefix=f".{name}-staging-", dir=cache_dir))
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
    dst = pathlib.Path(entry["install_to"]).expanduser()
    refuse_if_unowned(dst, name)
    if dst.is_symlink() or dst.exists():
        if not dry:
            if dst.is_symlink(): dst.unlink()
            elif dst.is_dir():    shutil.rmtree(dst)
            else:                  dst.unlink()
    if not dry:
        dst.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.symlink(cache.resolve(), dst)
        except OSError:
            shutil.copytree(cache, dst)
            write_sentinel(dst, f"git:{repo}@{ref}")
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
