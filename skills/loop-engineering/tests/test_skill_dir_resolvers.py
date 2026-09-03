#!/usr/bin/env python3
"""Execute the SKILL_DIR resolver snippets that SKILL.md ships.

These five shell one-liners are copy-pasted by an agent before it can run
anything else in this skill, and until now nothing ran them. A resolver that
silently returns a wrong-but-non-empty path is the worst failure available
here: the caller's own `[ -n "$SKILL_DIR" ]` guard passes and the skill
proceeds against a directory that does not exist.

The snippets are read out of SKILL.md rather than restated, so an edit to the
documented command is graded by this fixture instead of drifting past it.

Every snippet is asserted twice -- it must resolve when the skill is planted,
and it must return the empty string when it is not. The second half is the
red case: a resolver hard-coded to print nothing would pass the first half.
"""

from __future__ import annotations

import re
import subprocess
import tempfile
import unittest
from pathlib import Path

SKILL = Path(__file__).resolve().parent.parent / "SKILL.md"
HEADING = "## Resolve the skill directory"
# Every root the snippets search, relative to the hermetic $HOME or cwd.
HOME_ROOTS = (".claude/skills", ".agents/skills", ".cursor/skills")


def snippets() -> list[tuple[str, str]]:
    """(label, command) for each resolver line in SKILL.md's bash block."""
    text = SKILL.read_text()
    if HEADING not in text:
        raise AssertionError("SKILL.md lost the %r section" % HEADING)
    block = text.split(HEADING, 1)[1].split("```bash", 1)[1].split("```", 1)[0]
    found, label = [], None
    for line in block.splitlines():
        line = line.strip()
        if line.startswith("#"):
            label = line.lstrip("# ").rstrip(":")
        elif line.startswith("SKILL_DIR="):
            found.append((label or "unlabelled", line))
            label = None
    return found


class SkillDirResolverTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def plant(self, home: Path, repo: Path) -> None:
        """Put a loop_state.py in every root any snippet searches."""
        targets = [home / r / "loop-engineering" for r in HOME_ROOTS]
        targets.append(repo / "skills/loop-engineering")
        for target in targets:
            (target / "scripts").mkdir(parents=True, exist_ok=True)
            (target / "scripts/loop_state.py").write_text("")

    def resolve(self, command: str, home: Path, repo: Path) -> str:
        proc = subprocess.run(
            ["bash", "-c", command + '\nprintf "%s" "$SKILL_DIR"'],
            capture_output=True,
            text=True,
            env={"HOME": str(home), "PATH": "/usr/bin:/bin:/usr/local/bin"},
            cwd=str(repo),
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout.strip()

    def make_repo(self, name: str) -> Path:
        repo = self.root / name
        repo.mkdir()
        subprocess.run(
            ["git", "init", "-q", "."], cwd=str(repo), check=True,
            capture_output=True,
        )
        return repo

    def test_every_documented_snippet_is_covered(self) -> None:
        # A parse that matched nothing would make every test below vacuous.
        found = snippets()
        self.assertGreaterEqual(len(found), 5, [lbl for lbl, _ in found])
        joined = " ".join(lbl.lower() for lbl, _ in found)
        for host in ("claude", "codex", "cursor", "opencode", "fallback"):
            self.assertIn(host, joined)

    def test_snippets_resolve_a_planted_skill(self) -> None:
        for label, command in snippets():
            with self.subTest(label):
                home = self.root / re.sub(r"\W+", "-", label) / "home"
                home.mkdir(parents=True)
                repo = self.make_repo(re.sub(r"\W+", "-", label) + "-repo")
                self.plant(home, repo)
                got = self.resolve(command, home, repo)
                self.assertTrue(got, "%s resolved to nothing" % label)
                self.assertTrue(
                    Path(got).is_dir(), "%s -> missing dir %s" % (label, got)
                )
                self.assertEqual(Path(got).name, "loop-engineering", got)

    def test_snippets_return_empty_when_the_skill_is_absent(self) -> None:
        # The red case. Observed 2026-09-03: the opencode/worktree snippet
        # printed "$repo/skills/loop-engineering" for any git repo, whether or
        # not that directory existed, so `[ -n "$SKILL_DIR" ]` passed on a
        # path nothing could be read from.
        for label, command in snippets():
            with self.subTest(label):
                home = self.root / ("bare-" + re.sub(r"\W+", "-", label))
                (home / ".claude/skills").mkdir(parents=True)
                repo = self.make_repo("bare-" + re.sub(r"\W+", "-", label) + "-repo")
                got = self.resolve(command, home, repo)
                self.assertEqual(
                    got, "", "%s fabricated a path: %s" % (label, got)
                )

    def test_snippets_never_emit_a_relative_or_root_path(self) -> None:
        # A `dirname` chain over an empty match yields "." or "/", which reads
        # as a resolved directory and is the failure the SKILL.md comment
        # warns about by name.
        for label, command in snippets():
            with self.subTest(label):
                home = self.root / ("rel-" + re.sub(r"\W+", "-", label))
                (home / ".claude/skills").mkdir(parents=True)
                repo = self.make_repo("rel-" + re.sub(r"\W+", "-", label) + "-repo")
                got = self.resolve(command, home, repo)
                self.assertNotIn(got, (".", "/", "./..", ".."), label)


if __name__ == "__main__":
    unittest.main()
