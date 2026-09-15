"""Prevent plausible costs when model identity, rates or cache-write counts differ."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/codex_session_usage.py'
spec = importlib.util.spec_from_file_location('codex_usage', SCRIPT)
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


class RateBoundaries(unittest.TestCase):
    def run_reader(self, model, *, usage=None, flags=(), events=(), check=True):
        with tempfile.TemporaryDirectory(prefix='rate fixture ') as tmp:
            path = Path(tmp) / 'session.jsonl'
            rows = [
                {'type': 'session_meta', 'payload': {'id': 'session-id', 'model_provider': 'openai'}},
                {'type': 'turn_context', 'payload': {'model': model}},
                {'type': 'event_msg', 'payload': {'type': 'token_count', 'info': {
                    'total_token_usage': usage or {
                        'input_tokens': 1_000_000, 'cached_input_tokens': 400_000,
                        'cache_write_input_tokens': 200_000, 'output_tokens': 100_000}}}},
                *events,
            ]
            path.write_text('\n'.join(json.dumps(row) for row in rows))
            result = subprocess.run([sys.executable, str(SCRIPT), '--path', str(path), *flags],
                                    text=True, capture_output=True)
            if not check:
                return result
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)

    def test_only_exact_or_dated_known_models_match(self):
        for model in ['gpt-5.6-sol', 'gpt-6-astra', 'gpt-5-mini', 'gpt-4o-mini', 'o3-pro']:
            self.assertIsNone(reader.lookup_model_rates(model), model)
        self.assertEqual(reader.lookup_model_rates('gpt-5-2025-08-07'), reader.MODEL_RATES['gpt-5'])
        self.assertEqual(reader.lookup_model_rates('gpt-5-codex'), reader.MODEL_RATES['gpt-5-codex'])

    def test_unknown_models_preserve_current_identity_and_null_cost(self):
        for model in ['gpt-6-astra', 'gpt-5.6-sol']:
            data = self.run_reader(model)
            self.assertEqual(data['session_id'], 'session-id')
            self.assertEqual(data['model'], model)
            self.assertEqual(data['uncached_input_tokens'], 400_000)
            self.assertIsNone(data['usd_estimated'])

    def test_explicit_write_rate_prices_each_input_once(self):
        data = self.run_reader('gpt-6-astra', flags=(
            '--input-usd-per-mtok', '2', '--output-usd-per-mtok', '10',
            '--cache-read-usd-per-mtok', '0.2', '--cache-write-usd-per-mtok', '2.5'))
        self.assertAlmostEqual(data['usd_estimated'], 2.38)

    def test_unknown_or_partial_write_rates_do_not_guess(self):
        for model in ['gpt-5-codex', 'gpt-6-astra']:
            data = self.run_reader(model, flags=('--input-usd-per-mtok', '2'))
            self.assertIsNone(data['usd_estimated'])
            self.assertIsNone(data['usd_basis'])

    def test_legacy_no_write_counts_still_price_known_models(self):
        data = self.run_reader('gpt-5-codex', usage={
            'input_tokens': 1_000_000, 'cached_input_tokens': 500_000, 'output_tokens': 100_000})
        self.assertEqual(data['usd_estimated'], 1.6875)

    def test_invalid_counts_are_not_clamped_into_plausible_costs(self):
        for cached, written in [(800_000, 300_000), (-1, 0), (True, 0)]:
            data = self.run_reader('gpt-5-codex', usage={
                'input_tokens': 1_000_000, 'cached_input_tokens': cached,
                'cache_write_input_tokens': written, 'output_tokens': 1})
            self.assertIsNone(data['usd_estimated'])
            self.assertIsNone(data['uncached_input_tokens'])

    def test_invalid_rate_flags_fail(self):
        for rate in ['-1', 'nan', 'inf']:
            result = self.run_reader('gpt-6-astra', flags=('--input-usd-per-mtok', rate), check=False)
            self.assertEqual(result.returncode, 2)

    def test_mixed_models_do_not_price_all_cumulative_usage_at_latest_model(self):
        data = self.run_reader('gpt-6-astra', events=[
            {'type': 'turn_context', 'payload': {'model': 'gpt-5-codex'}},
            {'type': 'event_msg', 'payload': {'type': 'token_count', 'info': {'total_token_usage': {
                'input_tokens': 2_000_000, 'cached_input_tokens': 1_000_000, 'output_tokens': 200_000}}}},
        ])
        self.assertIsNone(data['model'])
        self.assertIsNone(data['usd_estimated'])


if __name__ == '__main__':
    unittest.main()
