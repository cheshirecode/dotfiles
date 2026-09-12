#!/usr/bin/env python3
"""Validate reference reachability and execute the examples readers copy."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from urllib.parse import unquote, urlsplit

SKILL = Path(__file__).resolve().parents[1]
LINK = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
EXAMPLE = re.compile(r"<!-- executable: ([\w-]+) -->\s*```bash\n(.*?)```", re.S)


def local_links(path: Path):
    for target in LINK.findall(path.read_text()):
        url = urlsplit(target)
        if not url.scheme:
            yield (path.parent / unquote(url.path)).resolve(), url.fragment


class DocumentationTest(unittest.TestCase):
    def test_local_links_and_heading_targets_resolve(self):
        for doc in SKILL.rglob("*.md"):
            for target, fragment in local_links(doc):
                with self.subTest(doc=doc.name, target=target, fragment=fragment):
                    self.assertTrue(target.is_file(), str(target))
                    if fragment:
                        headings = re.findall(r"^#+ (.+)$", target.read_text(), re.M)
                        anchors = {
                            re.sub(r"[^\w -]", "", h.lower()).replace(" ", "-")
                            for h in headings
                        }
                        self.assertIn(fragment, anchors)

    def test_every_reference_is_reachable_from_entrypoint(self):
        pending = [SKILL / "SKILL.md"]
        seen = set()
        while pending:
            path = pending.pop().resolve()
            if path in seen or not path.is_file():
                continue
            seen.add(path)
            pending.extend(p for p, _ in local_links(path) if p.suffix == ".md")
        self.assertFalse({p.resolve() for p in SKILL.rglob("*.md")} - seen)

    def test_root_uses_portable_frontmatter(self):
        text = (SKILL / "SKILL.md").read_text()
        frontmatter = text.split("---", 2)[1]
        keys = set(re.findall(r"^(\S+):", frontmatter, re.M))
        self.assertEqual(keys, {"name", "description"})
        self.assertNotIn("!`", text)

    def test_documented_examples_execute_and_preserve_state_contract(self):
        examples = EXAMPLE.findall((SKILL / "references/examples.md").read_text())
        self.assertEqual(
            {name for name, _ in examples},
            {"verified-loop", "bound-successor", "verdict-exit"},
        )
        with tempfile.TemporaryDirectory(prefix="loop docs ") as tmp:
            root = Path(tmp)
            env = dict(os.environ)
            for key in list(env):
                if key.startswith("WORKLOG_"):
                    env.pop(key)
            env.update(
                SKILL_DIR=str(SKILL),
                EVIDENCE_GATE=str(SKILL.parent / "evidence-gate/scripts/evidence_gate.py"),
                RUN_ROOT=tmp,
                HOME=tmp,
                GIT_CONFIG_NOSYSTEM="1",
                GIT_CONFIG_GLOBAL=os.devnull,
            )
            repo = root / "code repo"
            repo.mkdir()
            for args in (
                ["init", "-q"],
                ["-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", "fixture"],
            ):
                subprocess.run(["git", "-C", str(repo), *args], env=env, check=True,
                               capture_output=True)
            helpers = root / "queue helpers"
            helpers.mkdir()
            queue = helpers / "project.sh"
            queue.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' '{\"schema_version\":\"worklog-project-next/v1\","
                '\"project\":\"docs-example\",\"status\":\"eligible\",'
                '\"task\":\"next-child\"}\'\n'
            )
            queue.chmod(0o755)
            env.update(REPO=str(repo), PROJECT="docs-example", WORKLOG_BIN=str(helpers))
            outputs = {}
            for name, script in examples:
                with self.subTest(example=name):
                    result = subprocess.run(
                        ["/bin/bash", "-c", script], cwd=tmp, env=env,
                        text=True, capture_output=True, timeout=30,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    outputs[name] = result.stdout
            completed = json.loads((root / "verified/loop_state.json").read_text())
            self.assertEqual(completed["terminal_status"], "complete")
            self.assertTrue(completed["verification"].startswith("evidence-gate:"))
            self.assertEqual(completed["next_action"], "")
            predecessor = json.loads((root / "blocked/loop_state.json").read_text())
            successor = json.loads((root / "successor/loop_state.json").read_text())
            self.assertEqual(predecessor["terminal_status"], "blocked")
            self.assertEqual(successor["terminal_status"], "running")
            self.assertEqual(successor["goal"], predecessor["goal"])
            self.assertEqual(successor["budget"]["used"], 1)
            self.assertEqual(
                json.loads((root / "successor/run.json").read_text()),
                json.loads((root / "blocked/run.json").read_text()),
            )
            last_line = outputs["bound-successor"].splitlines()[-1]
            self.assertIn("queue: next-child", last_line)
            self.assertIn("radar: single-owner", last_line)
            self.assertEqual(json.loads((root / "verdict.json").read_text())["warn"], 1)


if __name__ == "__main__":
    unittest.main()
