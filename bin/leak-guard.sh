#!/usr/bin/env bash
# Reject work identifiers and hardcoded home paths.
#
#   --tree     scan tracked files (suite gate)
#   --staged   scan staged added lines (commit gate)
#
# Exit 0 clean, 1 findings, 2 usage.
#
# Per-line exemption: `pragma: allowlist owner`. Never exempt a whole file.
# Matcher is Python, not grep: grep -P is unavailable or differs (ugrep, BSD).
# Pattern list lives here only; the hook and the suite both call this script.

set -uo pipefail

MODE="${1:---tree}"
case "$MODE" in
  --tree|--staged) ;;
  *) echo "usage: leak-guard.sh [--tree|--staged]" >&2; exit 2 ;;
esac
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 2

MODE="$MODE" python3 - <<'SCAN'
import os
import re
import subprocess
import sys

# Owner-shaped literals: each named explicitly, so placeholders (<work-org>,
# other-owner, example-org) are the intended form and never match. A new
# employer goes on this list rather than behind a broad class.
OWNERS = ["ideogram", "textemma", "coderv2"]  # pragma: allowlist owner

# Home paths: a REAL username is a leak; a placeholder is the correct way to
# write an example. Banning every /home/<x>/ would fail a WSL tutorial's
# /home/user/project, and the usual response to that is to delete the check.
PLACEHOLDERS = {"user", "username", "yourusername", "youruser", "yourname",
                "name", "me", "you", "someone", "fredtran-example"}
HOME_RE = re.compile(r"/(?:Users|home)/([A-Za-z0-9_.-]+)/")
OWNER_RE = re.compile("|".join(OWNERS), re.I)
SKIP_SUFFIX = (".png", ".jpg", ".jpeg", ".gif", ".pdf", ".ico", ".zip", ".woff",
               ".woff2", ".ttf", ".pyc", ".lock")

def offenders_in(where, line):
    if "pragma: allowlist owner" in line:
        return []
    out = []
    m = OWNER_RE.search(line)
    if m:
        out.append(f"{where}: {m.group(0)!r}")
    for m in HOME_RE.finditer(line):
        who = m.group(1)
        if (who.lower() not in PLACEHOLDERS and not who.startswith("<")
                and not who.startswith(".")):
            out.append(f"{where}: hardcoded home path {m.group(0)!r}")
    return out

found = []
if os.environ["MODE"] == "--tree":
    files = subprocess.run(["git", "ls-files", "-z"], capture_output=True,
                           text=True, check=True).stdout.split("\0")
    for path in filter(None, files):
        if path.endswith(SKIP_SUFFIX):
            continue
        try:
            with open(path, encoding="utf-8") as handle:
                for n, line in enumerate(handle, 1):
                    found += offenders_in(f"{path}:{n}", line.rstrip("\n"))
        except (OSError, UnicodeDecodeError):
            continue
else:
    # Only ADDED lines. Existing content is grandfathered on purpose: this gate
    # stops NEW leakage instead of demanding a tree-wide cleanup before anyone
    # can commit. --tree holds the whole repo to the same bar in the suite.
    diff = subprocess.run(
        ["git", "diff", "--cached", "--unified=0", "--no-color",
         "--diff-filter=ACMR"], capture_output=True, text=True).stdout
    path = "staged"
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
        elif line.startswith("+") and not line.startswith("+++"):
            found += offenders_in(path, line[1:])

if found:
    sys.stderr.write("leak-guard: content that must not reach a public repo:\n")
    for row in found[:20]:
        sys.stderr.write(f"  {row[:140]}\n")
    if len(found) > 20:
        sys.stderr.write(f"  ... and {len(found) - 20} more\n")
    sys.stderr.write(
        "\n  Real values belong in the per-clone .envrc, never in the repo.\n"
        "  Describe a hazard by its shape; use placeholder owners in fixtures.\n"
        "  Deliberate exception: add 'pragma: allowlist owner' to the line.\n"
        '  See CLAUDE.md "Repo identity". Bypass once: DOTFILES_NO_HOOK=1\n')
    raise SystemExit(1)
SCAN
