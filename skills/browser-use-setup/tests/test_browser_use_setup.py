#!/usr/bin/env python3
"""Contracts for the browser-use-setup skill.

Three artifacts are pinned: the thin-root SKILL.md routing document, the
installer (bin/install-browser-use.sh), and the wrapper (bin/bu). The vendor
`browser-use skill install` command owns the ~/.claude/skills/browser-use/
namespace -- that is why this skill is named browser-use-setup, and the test
asserts the name so nobody "fixes" it into a collision that lets the vendor
overwrite our SKILL.md through install.sh's symlink.

The installer's cross-platform surface is tested here without network:
--help contract, the missing-uv refusal (exit 2, named fix, not a traceback),
and the Windows refusal. The real install (network + uv) is exercised by the
sandbox runs and the Dockerfile.test-matrix stage, not by unit fixtures.
"""

from __future__ import annotations

import pathlib
import subprocess
import unittest

SKILL_DIR = pathlib.Path(__file__).resolve().parents[1]
SKILL_MD = SKILL_DIR / "SKILL.md"
INSTALLER = SKILL_DIR / "bin" / "install-browser-use.sh"
WRAPPER = SKILL_DIR / "bin" / "bu"
PLATFORMS_MD = SKILL_DIR / "references" / "platforms.md"


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, check=False, **kwargs)


class SkillDocContract(unittest.TestCase):
    def test_frontmatter_name_matches_directory(self) -> None:
        text = SKILL_MD.read_text()
        head = text.split("---", 2)[1]
        self.assertIn("name: browser-use-setup", head)
        # Deliberately NOT "browser-use": the vendor skill install owns that
        # directory name in every harness root, and install.sh symlinks this
        # directory to the same paths. Same name = the vendor overwrites our
        # SKILL.md through the symlink.
        self.assertNotIn("name: browser-use\n", head)

    def test_thin_root_and_lazy_routes(self) -> None:
        text = SKILL_MD.read_text()
        lines = text.splitlines()
        self.assertLessEqual(len(lines), 60, "root must stay thin; push detail to references/")
        self.assertIn("bin/install-browser-use.sh", text, "install route")
        self.assertIn("bin/bu", text, "wrapper route")
        self.assertIn("references/platforms.md", text, "platform notes route")
        self.assertIn("Do not preload", text, "references must load on demand")

    def test_platforms_reference_exists_and_is_loaded_lazily(self) -> None:
        text = PLATFORMS_MD.read_text()
        self.assertIn("Linux", text)
        self.assertIn("macOS", text)


class InstallerContract(unittest.TestCase):
    def test_help_exits_zero_without_network(self) -> None:
        result = run(["bash", str(INSTALLER), "--help"])
        self.assertEqual(result.returncode, 0, result.stderr)
        for flag in ("--bootstrap-uv", "--no-skill", "--strict-doctor"):
            self.assertIn(flag, result.stdout + result.stderr)

    def test_missing_uv_refuses_with_named_fix(self) -> None:
        # PATH stripped to system dirs so `uv` cannot be found. The refusal
        # must name uv and offer the bootstrap path -- not a bare command-
        # not-found traceback from some later line.
        result = run(
            ["bash", str(INSTALLER)],
            env={"PATH": "/usr/bin:/bin", "HOME": "/tmp"},
        )
        self.assertEqual(result.returncode, 2, f"stderr: {result.stderr}")
        self.assertIn("uv", result.stderr)
        self.assertIn("--bootstrap-uv", result.stderr)

    def test_windows_refuses_with_wsl_guidance(self) -> None:
        result = run(
            ["bash", str(INSTALLER), "--help"],
            env={"PATH": "/usr/bin:/bin", "HOME": "/tmp", "BU_SETUP_FAKE_OS": "MINGW64_NT"},
        )
        # --help short-circuits before the OS gate, so drive the gate itself
        # through the test seam instead: a fake uname answer.
        self.assertEqual(result.returncode, 0)
        gate = run(
            ["bash", str(INSTALLER)],
            env={
                "PATH": "/usr/bin:/bin",
                "HOME": "/tmp",
                "BU_SETUP_FAKE_OS": "MINGW64_NT-10.0",
                "BU_SETUP_FAKE_OS_TEST": "1",
            },
        )
        self.assertEqual(gate.returncode, 1, gate.stderr)
        self.assertIn("WSL", gate.stderr)


class WrapperContract(unittest.TestCase):
    def test_help_exits_zero(self) -> None:
        result = run([str(WRAPPER), "--help"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--ensure", result.stdout + result.stderr)

    def test_missing_binary_refuses_with_install_pointer(self) -> None:
        result = run([str(WRAPPER), "--version"], env={"PATH": "/usr/bin:/bin", "HOME": "/tmp"})
        self.assertEqual(result.returncode, 127, f"stderr: {result.stderr}")
        self.assertIn("install-browser-use.sh", result.stderr)

    def test_ensure_flag_installs_before_use(self) -> None:
        # Prove the flag routes to the installer without hitting the network:
        # a stripped PATH makes the installer itself refuse with exit 2 (the
        # missing-uv contract above), which the wrapper must surface as its
        # own failure -- not silently exec a nonexistent binary.
        result = run(
            [str(WRAPPER), "--ensure", "--version"],
            env={"PATH": "/usr/bin:/bin", "HOME": "/tmp"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("uv", result.stderr)


class ScriptSyntax(unittest.TestCase):
    def test_both_scripts_parse(self) -> None:
        for script in (INSTALLER, WRAPPER):
            result = run(["bash", "-n", str(script)])
            self.assertEqual(result.returncode, 0, f"{script.name}: {result.stderr}")


if __name__ == "__main__":
    unittest.main()
