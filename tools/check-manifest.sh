#!/usr/bin/env bash
# Validate manifest/skills.yaml. Council-derived guardrails (#7):
#
#  - type:git entries MUST pin a 40-hex SHA (set INSTALL_SKILLS_ALLOW_MOVING_REF=1
#    on the install path if you really need a moving ref).
#  - type:subpath entries MUST NOT carry a `repo:` field (silently ignored
#    today, which lets typos lie).
#  - install_to paths must be unique (no two entries clobbering each other).
#  - all required keys present.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/manifest/skills.yaml"

python3 - "$MANIFEST" <<'PY'
import sys, re, yaml
m = yaml.safe_load(open(sys.argv[1]))
problems = []
seen_install_to = {}
seen_names = set()

for s in m.get("skills", []):
    name = s.get("name", "?")
    if not name or name in seen_names:
        problems.append(f"{name}: duplicate or missing name")
    seen_names.add(name)
    for key in ("description", "source", "install_to"):
        if key not in s:
            problems.append(f"{name}: missing required key '{key}'")
    src = s.get("source", {})
    stype = src.get("type")
    if stype not in ("subpath", "git"):
        problems.append(f"{name}: source.type='{stype}' (want 'subpath' or 'git')")
    if stype == "subpath" and src.get("repo"):
        # repo: is silently ignored for subpath sources; tolerating it lets
        # typos lie. Hard fail.
        problems.append(f"{name}: source.type='subpath' must not carry 'repo:' field")
    if stype == "git":
        ref = src.get("ref", "")
        if not re.fullmatch(r"[0-9a-f]{40}", ref):
            problems.append(f"{name}: source.ref='{ref}' not a 40-hex SHA (type:git requires SHA pinning)")
    inst = s.get("install_to")
    if inst in seen_install_to:
        problems.append(f"{name}: install_to '{inst}' collides with '{seen_install_to[inst]}'")
    seen_install_to[inst] = name

if problems:
    print("check-manifest: FAIL")
    for p in problems:
        print(f"  - {p}")
    sys.exit(1)
print(f"check-manifest: OK ({len(seen_names)} skills, install_to unique, refs valid)")
PY
