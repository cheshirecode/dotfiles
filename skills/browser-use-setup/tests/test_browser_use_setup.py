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
import tempfile
import unittest

SKILL_DIR = pathlib.Path(__file__).resolve().parents[1]
SKILL_MD = SKILL_DIR / "SKILL.md"
INSTALLER = SKILL_DIR / "bin" / "install-browser-use.sh"
WRAPPER = SKILL_DIR / "bin" / "bu"
PLATFORMS_MD = SKILL_DIR / "references" / "platforms.md"



def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, check=False, **kwargs)


def _temp_dir(case: unittest.TestCase) -> pathlib.Path:
    """Python 3.9-safe TemporaryDirectory bound to the test lifecycle.

    TestCase.enterContext arrived in 3.11; the harness runs these fixtures with
    /usr/bin/python3 (3.9 on macOS), so enterContext AttributeErrors there even
    though uv/pytest on 3.13 stays green.
    """
    tmp = tempfile.TemporaryDirectory()
    case.addCleanup(tmp.cleanup)
    return pathlib.Path(tmp.name)


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


class CdpAutoWiring(unittest.TestCase):
    """On WSL, the browser lives on the Windows side and its CDP endpoint is
    only reachable through a portproxy at the WSL gateway IP. Wiring that up
    by hand (export BU_CDP_URL=http://<gw>:9223) is the step every new
    session forgets. The wrapper must do it: probe the known endpoints, set
    BU_CDP_URL, and exec -- while explicit env from the caller always wins."""

    @staticmethod
    def _fixture_env(tmp: pathlib.Path, *, reachable: str, fake_wsl: bool) -> dict[str, str]:
        bin_dir = tmp / "bin"
        bin_dir.mkdir(exist_ok=True)
        ip_stub = bin_dir / "ip"
        ip_stub.write_text("#!/usr/bin/env bash\necho 'default via 172.22.160.1 dev eth0'\n")
        ip_stub.chmod(0o755)
        curl_stub = bin_dir / "curl"
        if reachable == "portproxy":
            # Only the gateway:9223 endpoint answers (the portproxy lane).
            curl_stub.write_text(
                "#!/usr/bin/env bash\n"
                'case "$4" in\n'
                "  http://172.22.160.1:9223/*) printf '%s' '{\"Browser\":\"Chrome/153.0.8010.48\"}' ;;\n"
                "  *) exit 7 ;;\n"
                "esac\n"
            )
        elif reachable == "direct":
            # No portproxy: mirrored networking makes localhost:9222 answer.
            curl_stub.write_text(
                "#!/usr/bin/env bash\n"
                'case "$4" in\n'
                "  http://localhost:9222/*) printf '%s' '{\"Browser\":\"Chrome/153.0.8010.48\"}' ;;\n"
                "  *) exit 7 ;;\n"
                "esac\n"
            )
        else:
            curl_stub.write_text("#!/usr/bin/env bash\nexit 7\n")
        curl_stub.chmod(0o755)
        # Stand-in for the real CLI: print the BU_CDP_URL it received, or an
        # explicit marker when unset, so the assertion reads what the wrapper
        # actually passed through.
        child = bin_dir / "browser-use"
        child.write_text(
            '#!/usr/bin/env bash\n'
            'if [ -n "${BU_CDP_URL:-}" ]; then echo "CDP=$BU_CDP_URL"; else echo "CDP=<unset>"; fi\n'
        )
        child.chmod(0o755)
        env = {"PATH": f"{bin_dir}:/usr/bin:/bin", "HOME": "/tmp"}
        if fake_wsl:
            env["BU_SETUP_FAKE_WSL"] = "1"
        return env

    def _run(self, tmp: pathlib.Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        return run([str(WRAPPER), "--version"], env=env, timeout=30)

    def test_wsl_portproxy_endpoint_is_wired(self) -> None:
        tmp = _temp_dir(self)
        env = self._fixture_env(tmp, reachable="portproxy", fake_wsl=True)
        result = self._run(tmp, env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CDP=http://172.22.160.1:9223", result.stdout, result.stderr)
        self.assertIn("wired", result.stderr, "the one-line notice must say what it did")

    def test_wsl_mirrored_localhost_endpoint_is_wired(self) -> None:
        tmp = _temp_dir(self)
        env = self._fixture_env(tmp, reachable="direct", fake_wsl=True)
        result = self._run(tmp, env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CDP=http://localhost:9222", result.stdout)

    def test_no_endpoint_leaves_env_unset(self) -> None:
        # Nothing answers: the wrapper must not invent a URL. The real CLI's
        # own local-chrome flow applies instead.
        tmp = _temp_dir(self)
        env = self._fixture_env(tmp, reachable="none", fake_wsl=True)
        result = self._run(tmp, env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CDP=<unset>", result.stdout, result.stderr)
        self.assertNotIn("wired", result.stderr)

    def test_non_wsl_never_probes(self) -> None:
        # BU_SETUP_FAKE_WSL=0 forces the non-WSL branch (a plain Linux host
        # cannot be faked by unsetting the var on a WSL machine): with the
        # same portproxy fixture, the child must see no BU_CDP_URL. Guards
        # against wiring a gateway URL on a box with no Windows side.
        tmp = _temp_dir(self)
        env = self._fixture_env(tmp, reachable="portproxy", fake_wsl=False)
        env["BU_SETUP_FAKE_WSL"] = "0"
        result = self._run(tmp, env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CDP=<unset>", result.stdout)

    def test_explicit_env_wins_over_probe(self) -> None:
        tmp = _temp_dir(self)
        env = self._fixture_env(tmp, reachable="portproxy", fake_wsl=True)
        env["BU_CDP_URL"] = "http://caller-set.example:9999"
        result = self._run(tmp, env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CDP=http://caller-set.example:9999", result.stdout)
        self.assertNotIn("wired", result.stderr)

    def test_wsl_detected_from_proc_version_without_fake_flag(self) -> None:
        # The real detection path on this host: /proc/version says Microsoft.
        # Probe must run (and wire) without BU_SETUP_FAKE_WSL.
        proc = pathlib.Path("/proc/version")
        if not proc.exists():
            self.skipTest("not a Linux/WSL host")
        proc_version = proc.read_text()
        if "microsoft" not in proc_version.lower():
            self.skipTest("not a WSL host")
        tmp = _temp_dir(self)
        env = self._fixture_env(tmp, reachable="portproxy", fake_wsl=False)
        result = self._run(tmp, env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CDP=http://172.22.160.1:9223", result.stdout)


class ScriptSyntax(unittest.TestCase):
    def test_both_scripts_parse(self) -> None:
        for script in (INSTALLER, WRAPPER):
            result = run(["bash", "-n", str(script)])
            self.assertEqual(result.returncode, 0, f"{script.name}: {result.stderr}")


if __name__ == "__main__":
    unittest.main()
