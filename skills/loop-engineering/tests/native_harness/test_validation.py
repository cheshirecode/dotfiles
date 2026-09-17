import copy
import json
from pathlib import Path
import tempfile
import unittest

from validate import accepted, grade


class ValidationControls(unittest.TestCase):
    def test_incomplete_or_unmetered_success_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'fixture.json').write_text(json.dumps(
                {'status': 'ready', 'schema': 1, 'label': 'native harness fixture'}))
            final = grade(root)
        turn = {'status': 'completed', 'usage_complete': True,
                'timing': {'timing_valid': True, 'within_ceiling': True}}
        self.assertTrue(accepted(turn, final, {'valid': True}, [final]))
        for fault in ('empty', 'duplicate', 'wrong-total', 'unmetered', 'late', 'no-tool', 'scope'):
            with self.subTest(fault=fault):
                observed = copy.deepcopy(final); native = copy.deepcopy(turn)
                receipt = {'valid': True}; calls = [final]
                if fault == 'empty': observed['checks'] = []
                if fault == 'duplicate': observed['checks'][0] = observed['checks'][1]
                if fault == 'wrong-total': observed['total'] = 0
                if fault == 'unmetered': native['usage_complete'] = False
                if fault == 'late': native['timing']['within_ceiling'] = False
                if fault == 'no-tool': calls = []
                if fault == 'scope': receipt['valid'] = False
                self.assertFalse(accepted(native, observed, receipt, calls))

    def test_grade_rejects_missing_extra_fields_and_external_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); path = root / 'fixture.json'
            self.assertEqual(grade(root)['total'], 4)
            self.assertFalse(grade(root)['success'])
            data = {'status': 'ready', 'schema': 1, 'label': 'native harness fixture', 'extra': True}
            path.write_text(json.dumps(data))
            self.assertFalse(grade(root)['success'])
            path.unlink(); external = root / 'external'; external.write_text(json.dumps(data))
            path.symlink_to(external)
            self.assertEqual(grade(root)['passed'], 0)
