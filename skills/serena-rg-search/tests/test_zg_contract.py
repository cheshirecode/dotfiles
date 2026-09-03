#!/usr/bin/env python3
"""Pin the zg caveats this skill's own examples depend on.

Every command in SKILL.md is one an agent will paste. Three of them were wrong
until someone ran them (measured against zvec-grep 0.2.1 on 2026-09-03):

  zg query --rg --files | rg 'announcement'
      -> Error: --files changes rg output and cannot be used with managed --rg

  zg query --rg PATTERN            exits 0 when nothing matches; rg exits 1.
      So `rg PATTERN || echo absent` fires and the zg form never does. The doc
      called it "managed rg: same flags" and said to use it wherever you would
      type rg -- true of flags, false of the exit status every script branches
      on.

  zg query --fts "xyzzy plugh frotz nitfol"   -> 10 hits, exit 0.
      The indexed lanes return the top N by ranking, so they cannot express
      "not here". An agent asking "where is X handled?" gets a confident list
      whether or not X exists.

These assertions are hermetic on purpose -- they read SKILL.md and never
invoke zg. A test that skipped when zg was absent could not fail on any
machine without it, which is every machine these examples were wrong on.
The measured behaviour is pinned by naming the version it was measured
against; a claim about another tool goes stale silently otherwise.
"""

from __future__ import annotations

import pathlib
import re
import unittest

SKILL = pathlib.Path(__file__).resolve().parent.parent / "SKILL.md"


class ZgContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.text = SKILL.read_text()

    # The pattern must match `zg query --rg ... --files` as ONE command and
    # not a line that merely mentions both. The first draft here matched any
    # line containing both tokens and flagged the routing table's legitimate
    # "`zg query --rg` (fallback `rg` / `rg --files`)" -- two separate
    # commands in one cell. Backtick and pipe end a command, so they bound it.
    BROKEN_FILES = re.compile(r"zg query --rg[^`|\n]*--files")

    @staticmethod
    def executable_part(text: str) -> str:
        """Drop shell comments, so a WARNING about a command is not the command.

        Draft 2 flagged this file's own `# NOT \`zg query --rg --files\`:` note
        -- the third time in one fixture that the matcher hit a neighbour of
        its target rather than the target. What must not appear is the command
        someone could paste and run.
        """
        out = []
        for line in text.splitlines():
            stripped = line.lstrip()
            if stripped.startswith("#"):
                continue
            out.append(re.split(r"\s+#", line, maxsplit=1)[0])
        return "\n".join(out)

    def test_the_broken_files_example_is_gone(self) -> None:
        hit = self.BROKEN_FILES.search(self.executable_part(self.text))
        self.assertIsNone(
            hit, "SKILL.md documents `zg query --rg --files`: %s" % (hit.group(0) if hit else "")
        )

    def test_the_broken_files_pattern_can_actually_fire(self) -> None:
        # Red case for the matcher above: without it, a pattern that matches
        # nothing is indistinguishable from a clean SKILL.md.
        self.assertIsNotNone(
            self.BROKEN_FILES.search("zg query --rg --files | rg 'announcement'")
        )
        # ...and does not fire on the legitimate table row that broke draft 1.
        self.assertIsNone(
            self.BROKEN_FILES.search(
                "| Literal text | `zg query --rg` (fallback `rg` / `rg --files`) |"
            )
        )
        # ...nor on a warning ABOUT the command, which broke draft 2. A real
        # runnable line must still be caught after comment-stripping.
        warned = self.executable_part("rg --files | rg x   # NOT `zg query --rg --files`")
        self.assertIsNone(self.BROKEN_FILES.search(warned))
        runnable = self.executable_part("zg query --rg --files | rg x   # a real one")
        self.assertIsNotNone(self.BROKEN_FILES.search(runnable))

    def test_the_exit_status_divergence_is_stated(self) -> None:
        self.assertIn("exits 0 when it finds nothing", self.text)
        self.assertIn("`rg` exits 1", self.text)

    def test_the_skill_no_longer_claims_same_flags(self) -> None:
        # "same flags" plus "use it wherever you would type rg" is what made
        # the exit-status difference invisible.
        self.assertNotIn("same flags", self.text)
        self.assertNotIn("use it wherever you would type", self.text)

    def test_indexed_lanes_are_marked_unable_to_prove_absence(self) -> None:
        self.assertIn("cannot express", self.text)
        self.assertIn("always return hits", self.text)
        # And it must say what CAN prove an absence, or the warning is a
        # dead end rather than a route.
        self.assertIn("Confirm an absence with", self.text)

    def test_fts_is_marked_as_needing_the_index(self) -> None:
        # The doc annotated only the semantic form as needing `zg index`.
        self.assertIn("`--fts` needs the index too", self.text)
        self.assertIn("WORKSPACE_INDEX_NOT_FOUND", self.text)

    def test_the_measured_version_is_recorded(self) -> None:
        # Behaviour of another tool, asserted from a doc: name what it was
        # measured against so the next reader can tell whether it still holds.
        self.assertRegex(self.text, r"zvec-grep 0\.\d+\.\d+")

    def test_every_documented_zg_command_is_still_covered_here(self) -> None:
        # Guard against the pin going vacuous: if the examples block is
        # rewritten or removed, this suite must not silently pass over an
        # empty set.
        commands = re.findall(r"^\s*zg query .*$", self.text, re.MULTILINE)
        self.assertGreaterEqual(len(commands), 3, commands)


if __name__ == "__main__":
    unittest.main()
