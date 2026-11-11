"""Offline behavioral fixtures for feedback intake and recovery."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/watch.py'
spec = importlib.util.spec_from_file_location('watch', SCRIPT)
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)
ROOT = '1700000000.000001'
REPLY = '1700000001.000001'
SHA = 'a' * 40


class WatchTest(unittest.TestCase):
    def setUp(self):
        self.config = dict(workspace='fixture', channel='CEXAMPLE', thread_ts=ROOT,
                           scope='Named PR, preview only', stop_condition='User stop',
                           cadence_seconds=10, max_polls=20, run_seconds=1000, writes={})
        self.state = watch.init(self.config, 0)

    def event(self, event_type, now=1, **fields):
        self.state = watch.apply(self.state, dict(type=event_type, **fields), now)
        return self.state

    def poll(self, now=1, content='Fix narrow layout'):
        self.event('poll-start', now)
        return self.event('poll-result', now, complete=True, next_cursor='',
                          anchor={k: self.config[k] for k in ('workspace', 'channel', 'thread_ts')},
                          messages=[dict(ts=ROOT, content='Fixture root'), dict(ts=REPLY, content=content)])

    def case(self, stage='mapped', **extra):
        return self.event('case', id='layout', message_ts=REPLY,
                          revision=self.state['messages'][REPLY]['revision'], stage=stage,
                          given='Narrow viewport', when='Open drawer', then='Controls fit',
                          evidence='fixture://case', **extra)

    def read(self):
        self.event('read', message_ts=REPLY, revision=self.state['messages'][REPLY]['revision'])

    def test_partial_or_foreign_page_leaves_cursor_and_state_untouched(self):
        self.event('poll-start')
        before = copy.deepcopy(self.state)
        for fields in (dict(complete=False, next_cursor='next'), dict(complete=True, next_cursor='')):
            with self.assertRaises(ValueError):
                self.event('poll-result', anchor={}, messages=[], **fields)
            self.assertEqual(self.state, before)
        self.assertIsNone(self.state['cursor'])

    def test_repeat_read_deduplicates_reactions_do_not_change_revision(self):
        self.poll(); self.read(); self.case()
        before = copy.deepcopy(self.state['messages'])
        self.poll(now=12)
        self.assertEqual(self.state['messages'], before)
        self.assertFalse(self.state['cases']['layout']['superseded'])
        self.assertEqual(len(self.state['messages'][REPLY]['versions']), 1)

    def test_edit_supersedes_cases_and_preserves_failed_evidence(self):
        self.poll(); self.read(); self.case('failed')
        revision = self.state['messages'][REPLY]['revision']
        self.poll(now=12, content='Edited acceptance request')
        self.assertTrue(self.state['cases']['layout']['superseded'])
        self.assertEqual(self.state['cases']['layout']['attempts'][0]['stage'], 'failed')
        self.assertFalse(self.state['messages'][REPLY]['read'])
        with self.assertRaises(ValueError):
            self.event('read', message_ts=REPLY, revision=revision)

    def test_verified_requires_matching_deployed_revision(self):
        self.poll(); self.read(); self.case()
        with self.assertRaises(ValueError):
            self.case('verified', commit=SHA, deployed_commit=SHA)
        with self.assertRaises(ValueError):
            self.case('deployed', commit=SHA, deployed_commit='b' * 40)
        self.case('implemented', commit=SHA)
        self.case('deployed', commit=SHA, deployed_commit=SHA)
        self.case('failed', commit=SHA)
        self.case('verified', commit=SHA, deployed_commit=SHA)
        stages = [a['stage'] for a in self.state['cases']['layout']['attempts']]
        self.assertEqual(stages, ['mapped', 'implemented', 'deployed', 'failed', 'verified'])

    def test_no_slack_write_without_explicit_authorization(self):
        self.poll(); self.read()
        for kind in ('reaction', 'post'):
            with self.assertRaises(ValueError):
                self.event('effect-intent', key='eyes:' + REPLY, kind=kind,
                           message_ts=REPLY, emoji='eyes')
        self.assertEqual(self.state['effects'], {})

    def test_uncertain_write_reconciles_before_retry_and_done_is_deduped(self):
        self.config['writes'] = {'reaction': 'User explicitly asked for eyes acknowledgement'}
        self.state = watch.init(self.config, 0)
        self.poll(); self.read()
        fields = dict(key='eyes:' + REPLY, kind='reaction', message_ts=REPLY, emoji='eyes')
        self.event('effect-intent', **fields)
        with self.assertRaises(ValueError):
            self.event('effect-intent', **fields)
        self.event('pause')
        self.event('effect-receipt', key=fields['key'], outcome='not_sent', evidence='fixture://absence-proof')
        self.event('resume')
        self.event('effect-intent', **fields)
        self.event('effect-receipt', key=fields['key'], outcome='done', evidence='fixture://reaction')
        with self.assertRaises(ValueError):
            self.event('effect-intent', **fields)
        self.assertEqual(len(self.state['effects'][fields['key']]['attempts']), 2)
        self.assertEqual(self.state['cases'], {})  # eyes is never acceptance

    def test_post_intent_preserves_exact_text_and_batch_and_is_not_retried(self):
        self.config['writes'] = {'post': 'User explicitly authorized thread result replies'}
        self.state = watch.init(self.config, 0)
        self.poll(); self.read(); self.case()
        fields = dict(key='post:layout:' + SHA, kind='post', text='Codex: layout check passed.', case_ids=['layout'])
        self.event('effect-intent', **fields)
        with self.assertRaises(ValueError):
            self.event('effect-intent', **fields)
        self.assertEqual(self.state['effects'][fields['key']]['intent']['text'], fields['text'])
        self.assertEqual(self.state['effects'][fields['key']]['intent']['case_ids'], ['layout'])

    def test_backoff_provider_retry_after_and_three_failures_pause(self):
        for now in (1, 31, 61):
            self.event('poll-start', now)
            self.event('poll-failed', now, error='Connection unavailable', retry_after_seconds=30)
            with self.assertRaises(ValueError):
                self.event('poll-start', now + 1)
        self.assertEqual(self.state['mode'], 'paused')
        self.assertIsNone(self.state['cursor'])
        self.assertEqual(sum(bool(h['error']) for h in self.state['history']), 3)

    def test_cadence_and_interrupted_poll(self):
        self.event('poll-start')
        with self.assertRaises(ValueError):
            self.event('poll-start', 2)
        self.event('poll-failed', error='Interrupted')
        with self.assertRaises(ValueError):
            self.event('poll-start', 2)
        self.poll(now=12)
        with self.assertRaises(ValueError):
            self.event('poll-start', 13)

    def test_pause_stop_and_budget_cannot_be_bypassed_with_resume(self):
        self.event('pause')
        with self.assertRaises(ValueError):
            self.event('poll-start')
        self.event('resume')
        with self.assertRaises(ValueError):
            self.event('poll-start', 1001)
        with self.assertRaises(ValueError):
            self.event('resume', 1001)
        self.event('stop')
        with self.assertRaises(ValueError):
            self.event('resume')
        self.state = watch.init(dict(self.config, max_polls=1), 0)
        self.poll()
        with self.assertRaises(ValueError):
            self.event('poll-start', 12)
        with self.assertRaises(ValueError):
            self.event('resume', 12)

    def test_atomic_cli_round_trip_and_rejected_transaction(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); state = root / 'watch'; data = root / 'input.json'
            def cli(command, value=None):
                if value is not None:
                    data.write_text(json.dumps(value))
                return subprocess.run([sys.executable, str(SCRIPT), '--state', str(state), command,
                                       '--input', str(data)], capture_output=True, text=True)
            self.assertEqual(cli('init', self.config).returncode, 0)
            self.assertNotEqual(cli('init', self.config).returncode, 0)
            self.assertEqual(cli('apply', dict(type='poll-start')).returncode, 0)
            before = (state / 'state.json').read_bytes()
            self.assertNotEqual(cli('apply', dict(type='poll-result', complete=False)).returncode, 0)
            self.assertEqual((state / 'state.json').read_bytes(), before)
            self.assertEqual(os.stat(state / 'state.json').st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(cli('show').stdout)['polls'], 1)
            self.assertFalse(list(state.glob('.state-*')))


if __name__ == '__main__':
    unittest.main()
