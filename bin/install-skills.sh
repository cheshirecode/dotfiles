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

def install_subpath(entry):
    src = repo_root / entry["source"]["path"]
    dst = pathlib.Path(entry["install_to"]).expanduser()
    if not src.exists():
        print(f"  SKIP {entry['name']}: source {src} not present (skill not vendored yet)")
        return False
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
    return True

def install_git(entry):
    name = entry["name"]
    repo = entry["source"]["repo"]
    ref = entry["source"]["ref"]
    cache = cache_dir / name
    if not cache.exists():
        print(f"  clone {name}: {repo} → {cache}")
        run(["git", "clone", "--quiet", f"https://github.com/{repo}.git", str(cache)])
    else:
        print(f"  pull  {name}: {cache}")
        run(["git", "-C", str(cache), "fetch", "--quiet"])
    print(f"  checkout {name}: {ref}")
    run(["git", "-C", str(cache), "checkout", "--quiet", ref])
    dst = pathlib.Path(entry["install_to"]).expanduser()
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
