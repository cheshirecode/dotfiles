"""The manual annotation preserves the reader's reported estimate basis."""
from pathlib import Path
import json
import os
import re
import subprocess
import unittest

SKILL = Path(__file__).resolve().parents[1]


def render_notes(document, basis):
    helper = re.search(r'key\(\) \{.*?\n\}', document, re.S).group(0)
    note = re.search(r'^  --notes (.*)$', document, re.M).group(1)
    env = dict(os.environ, USAGE=json.dumps({'usd_basis': basis}), READER='synthetic-reader')
    return subprocess.check_output(
        ['bash', '-c', helper + '\nprintf "%s" ' + note], env=env, text=True
    )


class AnnotationRecipeTest(unittest.TestCase):
    def test_notes_follow_reader_basis(self):
        document = (SKILL / 'references/annotate.md').read_text()
        for basis in ('model-rates', 'default-rates', 'provider-reported'):
            with self.subTest(basis=basis):
                notes = render_notes(document, basis)
                self.assertIn('USD basis: ' + basis, notes)
                self.assertIn('cached tokens are not added again', notes)


if __name__ == '__main__':
    unittest.main()
