"""The author-facing opt-in is also the validator's canonical form."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('opt_ins', ROOT / 'tools/check-skill-opt-ins.py')
opt_ins = importlib.util.module_from_spec(spec)
spec.loader.exec_module(opt_ins)


class CanonicalOptInTest(unittest.TestCase):
    def test_home_needs_only_the_author_facing_preamble(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / 'skills/example-led-instructions/SKILL.md'
            home.parent.mkdir(parents=True)
            home.write_text(
                'For brittle outputs, invoke `$example-led-instructions`: '
                '0/1/few-shot gate, max 1-3 examples, skip if obvious.\n'
                + '\n'.join(opt_ins.OUTPUT_FIELDS) + '\n'
            )
            problems = []
            opt_ins.validate_home_skill(root, problems)
            self.assertEqual(problems, [])


if __name__ == '__main__':
    unittest.main()
