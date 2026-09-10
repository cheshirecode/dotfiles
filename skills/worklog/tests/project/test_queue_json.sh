#!/usr/bin/env bash
set -euo pipefail
WORKLOG_BIN="$(cd "$(dirname "$0")/../../bin" && pwd)"
export WORKLOG_BIN
python3 - <<'PY'
import json, os, pathlib, subprocess, tempfile, unittest
import yaml

class Queue(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = pathlib.Path(self.tmp.name)
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True)
        self.env = {**os.environ, 'WORKLOG_REPO': str(self.repo), 'WORKLOG_LDAP': 'tester'}
        self.env.pop('BASH_ENV', None)
        self.active = self.repo/'people/tester/active'
        self.active.mkdir(parents=True)
        self.write('program', kind='project', tasks=[{'slug':'a'}, {'slug':'b','depends_on':['a']}])
        self.write('a', parent_slug='program')
        self.write('b', parent_slug='program')

    def write(self, slug, **fm):
        (self.active/(slug+'.md')).write_text('---\n'+yaml.safe_dump({'slug':slug,'status':'draft','next_action':'Verify rollup',**fm})+'---\n')

    def call(self, *args):
        return subprocess.run([os.environ['WORKLOG_BIN']+'/project.sh', *args],
                              cwd=self.repo, env=self.env, text=True, capture_output=True)

    def status(self, want, rc, slug='program'):
        result = self.call('next', slug, '--json')
        self.assertEqual(result.returncode, rc, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data['schema_version'], 'worklog-project-next/v1')
        self.assertEqual(data['status'], want)
        return data

    def test_order_and_archived(self):
        self.assertEqual(self.status('eligible',0)['task'], 'a')
        self.assertEqual(self.call('next','program').stdout.strip(), 'a')
        self.write('a', status='archived', parent_slug='program')
        self.assertEqual(self.status('eligible',0)['task'], 'b')
        self.write('b', status='archived', parent_slug='program')
        self.assertIsNone(self.status('empty',1)['task'])

    def test_missing_and_blocked(self):
        self.status('missing',1,'absent')
        (self.active/'a.md').unlink()
        self.status('missing',1)
        self.write('a', parent_slug='program')
        self.write('program', kind='project', tasks=[{'slug':'a','depends_on':['b']},{'slug':'b','depends_on':['a']}])
        self.status('blocked',1)

    def test_invalid_never_empty(self):
        for tasks in [[{}], ['bad'], [{'slug':'a','depends_on':'b'}], []]:
            with self.subTest(tasks=tasks):
                self.write('program', kind='project', tasks=tasks)
                self.status('error',1)
        self.write('program', kind='impl', tasks=[{'slug':'a'}])
        self.status('error',1)

    def test_peer_reverse_orphan_is_rejected(self):
        peer = self.repo/'people/peer/active'
        peer.mkdir(parents=True)
        (peer/'orphan.md').write_text('---\nslug: orphan\nparent_slug: program\nstatus: draft\n---\n')
        self.assertEqual(self.call('verify','program').returncode,2)

    def test_reverse_orphan_is_rejected(self):
        self.write('orphan', parent_slug='program', project='program')
        result = self.call('verify','program')
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn('orphan', result.stdout)

unittest.main()
PY
