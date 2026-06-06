#!/usr/bin/env python3
"""Cross-platform `flock(1)` substitute (macOS ships without /usr/bin/flock).

Usage:
  _flock.py <lockfile> -- <cmd> [args...]

Acquires an exclusive fcntl lock on <lockfile>, runs the command, releases.
Exit code is the command's exit code. If acquisition fails the process exits 1.
"""

from __future__ import annotations

import fcntl
import pathlib
import subprocess
import sys


def main() -> int:
  if len(sys.argv) < 4 or sys.argv[2] != "--":
    print("usage: _flock.py <lockfile> -- <cmd> [args...]", file=sys.stderr)
    return 2
  lockfile = pathlib.Path(sys.argv[1])
  cmd = sys.argv[3:]
  lockfile.parent.mkdir(parents=True, exist_ok=True)
  with open(lockfile, "w") as f:
    fcntl.flock(f.fileno(), fcntl.LOCK_EX)
    try:
      r = subprocess.run(cmd, check=False)
      return r.returncode
    finally:
      fcntl.flock(f.fileno(), fcntl.LOCK_UN)


if __name__ == "__main__":
  sys.exit(main())
