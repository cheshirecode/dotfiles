#!/usr/bin/env python3
"""Contract tests for the opt-in loop helpers and installer boundary."""

from __future__ import annotations

import json
import importlib.util
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import unittest


SKILL_DIR = pathlib.Path(__file__).parents[1]
REPO_ROOT = SKILL_DIR.parents[1]
CONTEXT_PACK = SKILL_DIR / "scripts/context_pack.py"
TRANSPORT_GATE = SKILL_DIR / "scripts/transport_gate.py"
INSTALL_SKILLS = REPO_ROOT / "bin/install-skills.sh"


class LoopHelpersTest(unittest.TestCase):
    def run_script(
        self,
        script: pathlib.Path,
        *arguments: str,
        env: dict[str, str] | None = None,
        expected_returncode: int = 0,
    ) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [sys.executable, str(script), *arguments],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            expected_returncode,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )
        return result

    def test_context_pack_is_compact_and_transcript_free(self) -> None:
        result = self.run_script(
            CONTEXT_PACK,
            "--objective",
            "reduce context",
            "--known-evidence",
            "command: tests passed",
            "--constraints",
            "isolated worktree",
            "--budget",
            "2 cycles",
            "--requested-return",
            "evidence and next action",
            "--recovery-handle",
            "ccr_123",
        )
        pack = json.loads(result.stdout)
        self.assertEqual(pack["schema_version"], 1)
        self.assertEqual(pack["known_evidence"], ["command: tests passed"])
        self.assertEqual(pack["recovery_handles"], ["ccr_123"])
        self.assertNotIn("parent transcript", result.stdout)
        self.assertNotIn("history", pack)

    def test_context_pack_requires_explicit_handoff_fields(self) -> None:
        self.run_script(
            CONTEXT_PACK,
            "--objective",
            "goal",
            expected_returncode=2,
        )

    def test_transport_gate_fails_open_when_capability_is_missing(self) -> None:
        environment = os.environ.copy()
        environment["PATH"] = str(pathlib.Path(self.tmpdir.name) / "empty-bin")
        result = self.run_script(
            TRANSPORT_GATE,
            "--mode",
            "pixel",
            "--authorized",
            env=environment,
        )
        self.assertIn("decision=skip mode=pixel reason=caveman-unavailable original-bytes", result.stdout)

    def test_transport_gate_requires_all_pixel_facts(self) -> None:
        fake = pathlib.Path(self.tmpdir.name) / "caveman"
        fake.write_text("#!/bin/sh\n")
        fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
        result = self.run_script(
            TRANSPORT_GATE,
            "--mode",
            "pixel",
            "--caveman-command",
            str(fake),
            "--authorized",
            "--measured-win",
            "--recoverable",
            "--dense",
            "--legible",
            "--model",
            "claude-fable-5",
        )
        self.assertIn("decision=use mode=pixel reason=all-gates-passed", result.stdout)

        sparse = self.run_script(
            TRANSPORT_GATE,
            "--mode",
            "pixel",
            "--caveman-command",
            str(fake),
            "--authorized",
            "--measured-win",
            "--recoverable",
            "--legible",
            "--model",
            "claude-fable-5",
        )
        self.assertIn("reason=payload-not-dense original-bytes", sparse.stdout)

    def test_default_install_skips_optional_helper_but_explicit_install_includes_it(self) -> None:
        if importlib.util.find_spec("yaml") is None:
            self.skipTest("PyYAML unavailable; bin/install-skills.sh already requires it")
        environment = os.environ.copy()
        environment["HOME"] = self.tmpdir.name
        yaml_origin = importlib.util.find_spec("yaml").origin
        environment["PYTHONPATH"] = str(pathlib.Path(yaml_origin).parent.parent)
        default = subprocess.run(
            [str(INSTALL_SKILLS), "--dry-run"],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )
        self.assertEqual(default.returncode, 0, default.stderr)
        self.assertIn("SKIP optional loop-helpers", default.stdout)

        included = subprocess.run(
            [str(INSTALL_SKILLS), "--dry-run", "--include-optional"],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )
        self.assertEqual(included.returncode, 0, included.stderr)
        self.assertIn("install loop-helpers:", included.stdout)

    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)


if __name__ == "__main__":
    unittest.main()
