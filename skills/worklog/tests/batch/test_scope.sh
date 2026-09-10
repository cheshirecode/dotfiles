#!/usr/bin/env bash
set -euo pipefail
WORKLOG_BIN="$(cd "$(dirname "$0")/../../bin" && pwd)"
export WORKLOG_BIN
python3 - <<'PY'
import json, os, pathlib, subprocess, tempfile, unittest, shutil

class BatchScope(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.repo = self.root / 'work'
        self.repo.mkdir()
        self.env = {**os.environ, 'WORKLOG_REPO': str(self.repo),
                    'WORKLOG_LDAP': 'tester', 'WORKLOG_NO_HOOK': '1'}
        self.env.pop('BASH_ENV', None)
        self.git('init', '-q')
        self.git('config', 'user.email', 'tester@example.com')
        self.git('config', 'user.name', 'Tester')
        subprocess.run(['git', 'init', '-q', '--bare', str(self.root/'remote.git')], check=True)
        self.git('remote', 'add', 'origin', str(self.root/'remote.git'))
        for owner, slug in [('peer', 'peer-only'), ('tester', 'first'), ('tester', 'second')]:
            p = self.repo / 'people' / owner / 'active' / (slug+'.md')
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(f'---\nslug: {slug}\nstatus: in-progress\nnext_action: Before\nlast_updated: 2020-01-01\n---\n## Context\nEvidence\n')
        (self.repo/'unrelated.txt').write_text('before\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'seed')
        self.git('branch', '-M', 'main')
        self.git('push', '-qu', 'origin', 'main')

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.repo, env=self.env,
                              text=True, capture_output=True, check=True).stdout

    def snapshot(self):
        return ({str(p.relative_to(self.repo)): p.read_bytes() for p in self.repo.glob('people/**/*.md')},
                self.git('diff', '--cached', '--binary'), self.git('rev-parse', 'HEAD'))

    def batch(self, records):
        return subprocess.run([os.environ['WORKLOG_BIN']+'/checkpoint-batch.sh'],
                              input=json.dumps(records), cwd=self.repo, env=self.env,
                              text=True, capture_output=True)

    def test_peer_namespace_refused_without_writes(self):
        before = self.snapshot()
        result = self.batch([{'slug': 'peer-only', 'next': 'Wrong owner'}])
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.snapshot(), before)

    def test_unrelated_index_refused_before_rewrites(self):
        (self.repo/'unrelated.txt').write_text('other session\n')
        self.git('add', 'unrelated.txt')
        before = self.snapshot()
        result = self.batch([{'slug': 'first', 'next': 'Changed'}])
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.snapshot(), before)

    def test_invalid_and_mixed_batch_refused(self):
        for slug in ['*', '../first', ['first'], 'missing']:
            with self.subTest(slug=slug):
                before = self.snapshot()
                result = self.batch([{'slug': 'first', 'next': 'Changed'}, {'slug': slug}])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.snapshot(), before)

    def test_symlinked_namespace_refused(self):
        shutil.rmtree(self.repo/'people/tester/active')
        (self.repo/'people/tester/active').symlink_to('../peer/active')
        before = (self.repo/'people/peer/active/peer-only.md').read_bytes()
        result = self.batch([{'slug':'peer-only','next':'Wrong owner'}])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.repo/'people/peer/active/peer-only.md').read_bytes(), before)

    def test_optional_field_types_are_validated_before_writes(self):
        for fields in [{'status':[]}, {'next':False}, {'pr':{'number':7}}]:
            with self.subTest(fields=fields):
                before = self.snapshot()
                result = self.batch([{'slug':'first','next':'Changed'}, {'slug':'second',**fields}])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.snapshot(), before)

    def test_staged_change_during_pull_is_not_committed(self):
        (self.repo/'unrelated.txt').write_text('other session\n')
        before = self.git('rev-parse','HEAD')
        wrapper = self.root/'wrapper'
        wrapper.mkdir()
        script = wrapper/'git'
        script.write_text('#!/bin/sh\nif [ "$1" = pull ]; then "$REAL_GIT" add unrelated.txt; fi\nexec "$REAL_GIT" "$@"\n')
        script.chmod(0o755)
        self.env.update(REAL_GIT=shutil.which('git'),PATH=str(wrapper)+os.pathsep+self.env['PATH'])
        result = self.batch([{'slug':'first','next':'Changed'}])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git('rev-parse','HEAD'),before)
        self.assertIn('unrelated.txt',self.git('diff','--cached','--name-only'))

    def test_valid_batch_commits_exact_paths(self):
        result = self.batch([{'slug': s, 'next': 'Verified'} for s in ['first', 'second']])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(self.git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD').splitlines()),
                         {'people/tester/active/first.md', 'people/tester/active/second.md'})

unittest.main()
PY
