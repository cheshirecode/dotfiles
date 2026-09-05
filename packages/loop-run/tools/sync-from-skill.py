#!/usr/bin/env python3
"""Regenerate the packaged looprun modules from the loop-engineering skill.

The skill (../../skills/loop-engineering) is canonical. loop_state.py and
bin/crew-radar are copied verbatim; loop_run.py gets exactly two mechanical
package adaptations (path constants, dual-mode sibling import). --check
diffs instead of writing, so CI fails on drift the moment the skill moves.
"""

from __future__ import annotations

import pathlib
import sys

PKG = pathlib.Path(__file__).resolve().parent.parent
SKILL = PKG.parent.parent / "skills" / "loop-engineering"

PATCHES = [
    (
        '''SKILL_DIR = Path(__file__).resolve().parent.parent
LOOP_STATE = SKILL_DIR / "scripts" / "loop_state.py"
CREW_RADAR = SKILL_DIR / "bin" / "crew-radar"''',
        '''# Package layout (loop-run library): loop_state.py sits beside this module
# and crew-radar ships inside the package. SKILL_DIR is kept for the
# optional worklog-queue lookup, which stays a soft dependency.
SKILL_DIR = Path(__file__).resolve().parent.parent
PKG_DIR = Path(__file__).resolve().parent
LOOP_STATE = PKG_DIR / "loop_state.py"
CREW_RADAR = PKG_DIR / "bin" / "crew-radar"''',
    ),
    (
        '''from loop_state import RESUMABLE_STATUSES, TERMINAL_STATUSES  # noqa: E402''',
        '''# Support both invocation styles: `python3 loop_run.py` (script) and
# `import looprun.loop_run` / console script (package).
try:
    from loop_state import RESUMABLE_STATUSES, TERMINAL_STATUSES  # noqa: E402
except ImportError:  # package import
    from looprun.loop_state import RESUMABLE_STATUSES, TERMINAL_STATUSES  # noqa: E402''',
    ),
]


def render() -> dict[pathlib.Path, str | bytes]:
    src = (SKILL / "scripts" / "loop_run.py").read_text()
    for old, new in PATCHES:
        if old not in src:
            sys.exit(f"sync: patch anchor missing in skill loop_run.py: {old.splitlines()[0]!r}")
        src = src.replace(old, new)
    return {
        PKG / "src/looprun/loop_run.py": src,
        PKG / "src/looprun/loop_state.py": (SKILL / "scripts" / "loop_state.py").read_text(),
        PKG / "src/looprun/bin/crew-radar": (SKILL / "bin" / "crew-radar").read_bytes(),
    }


def main() -> int:
    check = "--check" in sys.argv
    drift = 0
    for path, want in render().items():
        have = path.read_bytes() if path.exists() else b""
        want_bytes = want if isinstance(want, bytes) else want.encode()
        if have != want_bytes:
            drift += 1
            if check:
                print(f"DRIFT  {path.relative_to(PKG)}")
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(want_bytes)
                print(f"WROTE  {path.relative_to(PKG)}")
    if check and drift:
        print(f"sync: {drift} file(s) drifted from skills/loop-engineering — run tools/sync-from-skill.py")
        return 1
    print("sync: package matches the skill" if not drift else f"sync: regenerated {drift} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
