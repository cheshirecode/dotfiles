#!/usr/bin/env python3
"""Execute the documented fallback against isolated skill installations."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SKILL = Path(__file__).resolve().parents[1] / "SKILL.md"


class SkillRootTest(unittest.TestCase):
    def resolve(self, installed: tuple[str, ...], expected: str | None) -> None:
        recipe = SKILL.read_text().split("```bash\n", 1)[1].split("```", 1)[0]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            home, cwd = root / "home", root / "repo"
            home.mkdir()
            cwd.mkdir()
            for location in installed:
                catalog = root / location / "bin/model-catalog"
                catalog.parent.mkdir(parents=True)
                catalog.touch(mode=0o755)
            env = {
                "HOME": str(home),
                "PWD": str(cwd),
                "PATH": os.defpath,
                "SUPER_RULER": str(root / "absent-super-ruler"),
            }
            result = subprocess.run(
                ["/bin/bash", "--noprofile", "--norc", "-c", recipe],
                cwd=cwd, env=env, text=True, capture_output=True, check=True,
            )
            self.assertEqual(result.stdout.strip(), str(root / expected) if expected else "not found")

    def test_repo_payload_precedes_installed_copy(self) -> None:
        self.resolve(
            ("repo/skills/which-model", "home/.claude/which-model"),
            "repo/skills/which-model",
        )

    def test_shared_codex_install(self) -> None:
        self.resolve(("home/.agents/skills/which-model",), "home/.agents/skills/which-model")

    def test_codex_legacy_install(self) -> None:
        self.resolve(("home/.codex/skills/which-model",), "home/.codex/skills/which-model")

    def test_flattened_install(self) -> None:
        self.resolve(("home/.claude/which-model",), "home/.claude/which-model")

    def test_missing_payload(self) -> None:
        self.resolve((), None)


if __name__ == "__main__":
    unittest.main()
