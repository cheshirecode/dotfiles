"""Pin routing.md's Claude Code delegation aliases against the live catalog.

The alias set a dispatch call accepts (`sonnet`, `opus`, `haiku`, `fable`) is
coarser than the catalog's model ids, so the mapping between them is written
prose -- and prose drifts. A new model family in the catalog with no alias row
would be recommended for a delegate and then rejected at dispatch, which is
the failure this file exists to make loud.
"""

from __future__ import annotations

import json
import re
import subprocess
import unittest
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parent.parent
ROUTING = SKILL_ROOT / "references" / "routing.md"
CATALOG = SKILL_ROOT / "bin" / "model-catalog"

# Active but deliberately unaliased: no dispatch call can select them.
UNALIASED_FAMILIES = {"mythos"}


def documented_aliases() -> set[str]:
    """Aliases from the Claude Code lane table only.

    Scoped to that one section on purpose. A file-wide scan also matches the
    OpenCode table and the precedence list below it, which would make the set
    look complete no matter what the lane table said.
    """
    text = ROUTING.read_text()
    start = text.index("#### Claude Code")
    end = text.index("### Delegation model selection", start)
    section = text[start:end]
    aliases: set[str] = set()
    for row in section.splitlines():
        if not row.startswith("|") or "---" in row:
            continue
        cells = [c.strip() for c in row.strip("|").split("|")]
        if len(cells) < 2 or cells[1].lower().startswith("delegation alias"):
            continue
        aliases.update(re.findall(r"`([a-z]+)`", cells[1]))
    return aliases


def catalog_models() -> list[dict]:
    proc = subprocess.run(
        [str(CATALOG), "--env", "claude"],
        capture_output=True,
        text=True,
        timeout=120,
    )
    if proc.returncode != 0:
        raise unittest.SkipTest("model-catalog --env claude unavailable")
    return json.loads(proc.stdout)["catalog"]["models"]


def family(model_id: str) -> str | None:
    m = re.match(r"claude-([a-z]+)-", model_id)
    return m.group(1) if m else None


class DelegationAliasTest(unittest.TestCase):
    def setUp(self) -> None:
        self.models = catalog_models()
        self.aliases = documented_aliases()

    def test_lane_table_documents_the_four_dispatch_aliases(self) -> None:
        self.assertEqual(self.aliases, {"haiku", "sonnet", "opus", "fable"})

    def test_every_selectable_active_family_has_an_alias(self) -> None:
        missing = (
            {
                family(m["id"])
                for m in self.models
                if m.get("lifecycle") == "active"
                and m.get("availability") == "selectable_if_configured"
            }
            - self.aliases
            - UNALIASED_FAMILIES
        )
        self.assertEqual(
            missing,
            set(),
            "catalog families with no delegation alias row in routing.md: "
            f"{sorted(x for x in missing if x)}",
        )

    def test_unaliased_families_are_not_selectable(self) -> None:
        # If one of these ever becomes selectable it needs an alias row, and
        # the exemption above must go -- otherwise it is silently exempt from
        # the check that would have caught it.
        for m in self.models:
            if family(m["id"]) in UNALIASED_FAMILIES:
                self.assertNotEqual(
                    m.get("availability"),
                    "selectable_if_configured",
                    f"{m['id']} became selectable but has no alias row",
                )


if __name__ == "__main__":
    unittest.main()
