"""Both entrypoints run one scanner, including independently installed copies."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

SKILLS = Path(__file__).resolve().parents[2]


class ScannerCompatibilityTest(unittest.TestCase):
    def run_scanner(self, script, text, *args, **kwargs):
        return subprocess.run(['bash', str(script), *args], input=text,
                              text=True, capture_output=True, **kwargs)

    def test_both_paths_preserve_verdicts_and_arguments(self):
        for skill in ('pr-review', 'ship-hygiene'):
            script = SKILLS / skill / 'bin/leak-scan.sh'
            for text, expected in [('Valid product description', 0), ('next_action: internal', 1), ('', 2)]:
                with self.subTest(skill=skill, verdict=expected):
                    result = self.run_scanner(script, text, '--label', 'compat-test')
                    self.assertEqual(result.returncode, expected, result.stderr)
                    self.assertIn('compat-test', result.stdout + result.stderr)

    def test_separate_install_roots_and_missing_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            legacy = home / '.cursor/skills/ship-hygiene/bin/leak-scan.sh'
            legacy.parent.mkdir(parents=True)
            shutil.copy2(SKILLS / 'ship-hygiene/bin/leak-scan.sh', legacy)
            env = dict(os.environ, HOME=str(home))
            result = self.run_scanner(legacy, 'Valid product description', env=env, cwd=home)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn('pr-review', result.stderr)
            owner = home / '.agents/skills/pr-review/bin/leak-scan.sh'
            owner.parent.mkdir(parents=True)
            shutil.copy2(SKILLS / 'pr-review/bin/leak-scan.sh', owner)
            result = self.run_scanner(legacy, 'next_action: internal', '--label', 'installed', env=env, cwd=home)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn('installed', result.stdout)


if __name__ == '__main__':
    unittest.main()
