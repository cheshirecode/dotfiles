#!/usr/bin/env python3
"""Fixtures for deterministic loop-engineering installation audits."""

from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "scripts" / "install_audit.py"


class InstallAuditTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = pathlib.Path(self.temporary_directory.name)
        self.canonical = self.root / "canonical"
        self.canonical.mkdir()
        (self.canonical / "SKILL.md").write_text("canonical\n")
        (self.canonical / "scripts").mkdir()
        (self.canonical / "scripts/tool.py").write_text("print('ok')\n")

    def run_cli(
        self,
        *roots: pathlib.Path,
        link_identical: bool = False,
        expected_returncode: int = 0,
    ) -> tuple[subprocess.CompletedProcess[str], list[dict[str, str]]]:
        arguments = [
            sys.executable,
            str(SCRIPT),
            "--canonical",
            str(self.canonical),
            "--json",
        ]
        for root in roots:
            arguments.extend(("--root", str(root)))
        if link_identical:
            arguments.append("--link-identical")
        result = subprocess.run(arguments, capture_output=True, text=True, check=False)
        self.assertEqual(
            result.returncode,
            expected_returncode,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )
        return result, json.loads(result.stdout)

    def make_copy(self, name: str) -> pathlib.Path:
        destination = self.root / name
        shutil.copytree(self.canonical, destination)
        return destination

    def test_audit_classifies_source_link_copy_and_absence(self) -> None:
        linked = self.root / "linked"
        linked.symlink_to(self.canonical, target_is_directory=True)
        copied = self.make_copy("copied")
        absent = self.root / "absent"

        _, entries = self.run_cli(
            self.canonical,
            linked,
            copied,
            absent,
            expected_returncode=1,
        )

        self.assertEqual(
            [entry["status"] for entry in entries],
            ["source", "linked", "duplicate-identical", "absent"],
        )

    def test_repair_is_fail_closed_when_any_copy_diverges(self) -> None:
        identical = self.make_copy("identical")
        divergent = self.make_copy("divergent")
        (divergent / ".DS_Store").write_text("unexpected\n")

        result, entries = self.run_cli(
            identical,
            divergent,
            link_identical=True,
            expected_returncode=1,
        )

        self.assertIn("refusing all writes", result.stderr)
        self.assertEqual(
            [entry["status"] for entry in entries],
            ["duplicate-identical", "divergent-copy"],
        )
        self.assertTrue(identical.is_dir())
        self.assertFalse(identical.is_symlink())

    def test_repair_replaces_only_identical_copy_with_symlink(self) -> None:
        identical = self.make_copy("identical")

        _, entries = self.run_cli(identical, link_identical=True)

        self.assertEqual(entries[0]["status"], "linked")
        self.assertTrue(identical.is_symlink())
        self.assertEqual(identical.resolve(), self.canonical.resolve())


    def test_pycache_in_canonical_does_not_break_identical_detection(self) -> None:
        copied = self.make_copy("copied")
        pycache = self.canonical / "scripts" / "__pycache__"
        pycache.mkdir()
        (pycache / "tool.cpython-312.pyc").write_bytes(b"\x00machine-local")

        _, entries = self.run_cli(copied, expected_returncode=1)

        self.assertEqual(entries[0]["status"], "duplicate-identical")

    def test_nonexistent_canonical_exits_two_without_traceback(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--canonical",
                str(self.root / "missing"),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2, msg=result.stderr)
        self.assertIn("install-audit:", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_aliased_roots_are_deduplicated_before_repair(self) -> None:
        identical = self.make_copy("identical")
        alias_parent = self.root / "alias"
        alias_parent.symlink_to(self.root, target_is_directory=True)

        _, entries = self.run_cli(
            identical,
            alias_parent / "identical",
            link_identical=True,
        )

        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["status"], "linked")
        self.assertTrue(identical.is_symlink())
        stray = [p for p in self.root.iterdir() if ".backup-" in p.name]
        self.assertEqual(stray, [])


if __name__ == "__main__":
    unittest.main()
