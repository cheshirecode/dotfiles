"""Exercise fresh, existing, repeated, multi-vault, and rejected setup paths."""
import json
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("worklog_node", ROOT / "bin/worklog-mcp-node.py")
NODE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NODE)


class SetupTest(unittest.TestCase):
    def test_user_node_is_preserved(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {"XDG_DATA_HOME": tmp}), \
                patch.object(NODE.shutil, "which", return_value="/user/node"), \
                patch.object(NODE, "healthy", return_value=True), patch.object(NODE, "download") as download:
            self.assertEqual(NODE.resolve(), "/user/node")
            download.assert_not_called()
            self.assertEqual(list(Path(tmp).iterdir()), [])

    def test_corrupt_runtime_never_installs(self):
        filename = "node-v22.0.0-linux-x64.tar.xz"
        def download(_url, target, resume=False):
            target.write_bytes(("0" * 64 + "  " + filename + "\n").encode() if target.name == "SHASUMS256.txt" else b"corrupt")
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {"XDG_DATA_HOME": tmp}), \
                patch.object(NODE, "healthy", return_value=False), patch.object(NODE, "download", side_effect=download), \
                patch.object(NODE.platform, "system", return_value="Linux"), patch.object(NODE.platform, "machine", return_value="x86_64"):
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                NODE.resolve(managed=True)
            self.assertFalse((Path(tmp) / "worklog-mcp/node").exists())
            self.assertFalse((Path(tmp) / "worklog-mcp" / filename).exists())

    def test_config_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix="worklog-config-") as tmp:
            home = Path(tmp)
            env = {"HOME": tmp, "PATH": os.environ["PATH"], "CODEX_HOME": str(home / ".codex"), "XDG_CONFIG_HOME": str(home / ".config")}
            vaults = [home / "space one/_worklog", home / "space two/_worklog"]
            for vault in vaults:
                (vault / ".git").mkdir(parents=True)
                (vault / "people").mkdir()
            config = home / ".codex/config.toml"
            config.parent.mkdir()
            original = '# preserve this comment\nmodel = "keep"\n[mcp_servers.other]\ncommand = "keep"\n'
            config.write_text(original)
            claude = home / ".claude.json"
            claude.write_text(json.dumps({"custom": True, "mcpServers": {
                "other": {"command": "keep"},
                "legacy": {"command": "old", "disabled": True, "env": {"WORKLOG_REPO": str(vaults[0].resolve())}},
            }}))
            claude.chmod(0o640)
            (home / ".cursor").mkdir()
            (home / ".cursor/mcp.json").symlink_to(home / "cursor-real.json")
            cmd = ["python3", str(ROOT / "bin/configure-worklog-mcp.py")]
            for vault in vaults:
                cmd += ["--repo", str(vault)]
            def run(*flags):
                return subprocess.run([*cmd, *flags], env=env, capture_output=True, text=True)
            self.assertEqual(run("--dry-run").returncode, 0)
            self.assertEqual(config.read_text(), original)
            self.assertFalse((home / "cursor-real.json").exists())
            result = run()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(config.read_text().startswith(original))
            self.assertEqual(config.read_text().count("# dotfiles worklog MCP begin"), 2)
            data = json.loads(claude.read_text())
            self.assertTrue(data["custom"])
            self.assertEqual(data["mcpServers"]["other"]["command"], "keep")
            self.assertEqual(len(data["mcpServers"]), 3)
            self.assertTrue(data["mcpServers"]["legacy"]["disabled"])
            self.assertNotEqual(data["mcpServers"]["legacy"]["command"], "old")
            self.assertTrue((home / ".cursor/mcp.json").is_symlink())
            configs = [config, claude, home / ".cursor/mcp.json", home / ".config/opencode/opencode.json"]
            before = [p.read_bytes() for p in configs]
            self.assertEqual(run().returncode, 0)
            self.assertEqual([p.read_bytes() for p in configs], before)
            self.assertEqual(claude.stat().st_mode & 0o777, 0o640)  # existing permissions preserved
            self.assertEqual(configs[2].stat().st_mode & 0o777, 0o600)
            # A bad config late in the list must leave earlier configs unchanged.
            configs[2].write_text("broken json")
            claude.write_text('{"custom": true}')
            before = [p.read_bytes() for p in configs]
            self.assertNotEqual(run().returncode, 0)
            self.assertEqual([p.read_bytes() for p in configs], before)


if __name__ == "__main__":
    unittest.main()
