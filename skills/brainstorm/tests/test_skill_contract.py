"""Contract checks for skills/brainstorm/SKILL.md.

The skill owns the ideation recipe and must route evaluation to council.
The negative checks are the load-bearing half: they catch council
machinery (voting math, ballot shapes, iron-law text) leaking into this
file, which would create a second owner for those rules.
"""

import pathlib
import re
import unittest

SKILL = pathlib.Path(__file__).resolve().parents[1] / "SKILL.md"


class BrainstormContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SKILL.read_text()
        cls.flat = " ".join(cls.text.split())

    def test_frontmatter_shape(self):
        head = self.text.split("---", 2)[1]
        keys = re.findall(r"^(\w[\w-]*):", head, re.M)
        self.assertEqual(keys, ["name", "description"])

    def test_line_budget(self):
        self.assertLessEqual(len(self.text.splitlines()), 120)

    def test_owns_recipe_routes_council(self):
        # Ownership boundary: council named as the evaluation owner.
        self.assertIn("`$council` owns", self.flat)
        self.assertIn("keep-threshold iteration rule", self.flat)

    def test_four_angles_named(self):
        for angle in ("competition", "demand", "feasibility",
                      "distribution"):
            self.assertRegex(self.text, rf"\*\*{angle}\*\*")

    def test_exclusion_and_no_revote(self):
        self.assertIn("Exclude already-evaluated ideas", self.text)
        self.assertIn("never re-vote the same list", self.text)

    def test_no_council_machinery_duplicated(self):
        # Voting math, ballot line shapes, and iron-law names belong to
        # council. Any of these appearing here means a duplicated owner.
        for token in ("ceil(", "APPROVE_count", "QUALIFY_count",
                      "majority-plus-one", "REJECT-with",
                      "validate-ballot.py", "Iron Law"):
            self.assertNotIn(token, self.text, token)

    def test_artifacts_stay_out_of_worktree(self):
        self.assertIn("system temp", self.flat)
        self.assertIn(
            "Do not write seed or angle artifacts into the repo worktree",
            self.flat)


if __name__ == "__main__":
    unittest.main()
