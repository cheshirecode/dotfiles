#!/usr/bin/env python3
"""Assert SKILL.md frontmatter is well-formed and `name:` matches the dir name.

Usage: check-skill-frontmatter.py <SKILL.md path> <expected name>

Prints one of: OK, NO_FRONTMATTER, NO_NAME, NAME_MISMATCH:<actual>.
Exit code is always 0 — caller (bin/doctor.sh) consumes stdout.
"""

import re
import sys


def main() -> int:
    path, expected_name = sys.argv[1], sys.argv[2]
    text = open(path).read()
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        print("NO_FRONTMATTER")
        return 0
    block = m.group(1)
    nm = re.search(r"^name:\s*(\S+)", block, re.MULTILINE)
    if not nm:
        print("NO_NAME")
        return 0
    actual = nm.group(1).strip("\"'")
    if actual != expected_name:
        print(f"NAME_MISMATCH:{actual}")
        return 0
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
