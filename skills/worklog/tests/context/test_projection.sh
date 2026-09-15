#!/usr/bin/env bash
set -euo pipefail
WORKLOG_BIN="$(cd "$(dirname "$0")/../../bin" && pwd)"
export WORKLOG_BIN
python3 - <<'PY'
import json, os, pathlib, subprocess, tempfile, unittest
import yaml

class ContextProjection(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = pathlib.Path(self.tmp.name)
        self.active = self.repo/'people/tester/active'
        self.active.mkdir(parents=True)
        subprocess.run(['git','init','-q',str(self.repo)],check=True)
        self.file = self.active/'task.md'
        self.bin = self.repo/'fake-bin'
        self.bin.mkdir()
        self.calls = self.repo/'calls'
        gh = self.bin/'gh'
        gh.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALLS"\necho \'{"number":7,"title":"PR","state":"OPEN","url":"https://github.com/org/one/pull/7"}\'\n')
        gh.chmod(0o755)
        self.env = {**os.environ,'WORKLOG_REPO':str(self.repo),'WORKLOG_LDAP':'tester',
                    'WORKLOG_KNOWN_REPOS':'org/one,org/two','CALLS':str(self.calls),
                    'PATH':str(self.bin)+os.pathsep+os.environ['PATH']}
        self.env.pop('BASH_ENV',None)
        self.write()

    def write(self, **fm):
        front = {'slug':'task','status':'in-progress','next_action':'Verify "quoted" path \\ safely','pr':[7],**fm}
        self.file.write_text('---\n'+yaml.safe_dump(front)+'---\n## Context\n'+'evidence '*3000+'\n## Next\n'+''.join(f'- [ ] Check "item {i}" at C:\\path\n' for i in range(8)))

    def call(self,*args,check=True):
        return subprocess.run([os.environ['WORKLOG_BIN']+'/context.sh','task',*args],
                              cwd=self.repo,env=self.env,text=True,capture_output=True,check=check)

    def test_compact_json_bounded_and_no_pr_calls(self):
        result = self.call('--for=compact','--format=json')
        data = json.loads(result.stdout)
        self.assertFalse('body' in data)
        self.assertEqual(data['schema_version'],'worklog-context/v1')
        self.assertEqual(len(data['open_items']),5)
        self.assertEqual(data['omitted_items'],3)
        self.assertTrue(pathlib.Path(data['task_path']).is_absolute())
        self.assertTrue(pathlib.Path(data['task_path']).exists())
        self.assertEqual(len(data['content_sha256']),64)
        self.assertLess(len(result.stdout.encode()),2000)
        self.call('--for=compact')
        self.assertFalse(self.calls.exists())

    def test_tracker_selection_and_string_escaping(self):
        for host, wanted, absent in [('codex','update_plan(', 'TaskCreate('),('claude','TaskCreate(','update_plan(')]:
            out = self.call('--tracker='+host).stdout
            self.assertIn(wanted,out)
            self.assertNotIn(absent,out)
            self.assertIn('Verify before hydrating',out)
        out = self.call('--tracker=claude').stdout
        first = next(line for line in out.splitlines() if line.startswith('TaskCreate('))
        # The structured JSON argument preserves quoted commands as data.
        self.assertEqual(json.loads(first[len('TaskCreate('):-1])['description'],'Check "item 0" at C:\\path')
        neutral = self.call('--tracker=none').stdout
        self.assertNotIn('TaskCreate(',neutral)
        self.assertNotIn('update_plan(',neutral)
        legacy = self.call('--tracker=all').stdout
        self.assertIn('TaskCreate(',legacy)
        self.assertIn('update_plan(',legacy)

    def test_ambiguous_pr_is_not_guessed(self):
        self.write(repos=['org/one','org/two'])
        data = json.loads(self.call('--format=json').stdout)
        self.assertEqual(data['prs'],[])
        self.assertEqual(data['pr_diagnostics'][0]['status'],'ambiguous')
        self.assertFalse(self.calls.exists())

    def test_explicit_existing_pr_mapping_queries_one_repo(self):
        for key in [7,'7']:
            self.calls.unlink(missing_ok=True)
            self.write(pr_repos={key:'org/one'},repos=['org/one','org/two'])
            data = json.loads(self.call('--format=json').stdout)
            self.assertEqual(data['prs'][0]['repo'],'org/one')
            self.assertEqual(len(self.calls.read_text().splitlines()),1)
            self.assertIn('-R org/one',self.calls.read_text())
            self.assertIn('body',data)
            self.assertIn('work_items',data)

    def test_cache_and_context_share_kernel_parsing(self):
        long_command = 'command-'+'x'*250
        self.file.write_text("---\nslug: 'task'\nstatus: in-progress\nnext_action: >\n  Verify quoted\n  command\n---\n## Next\n- [ ] First line\n  "+long_command+"\n### Detail\n- [ ] Nested current item\n## Old notes\n## Next\n- [ ] Historical item\n")
        (self.active/'invalid.md').write_text('---\nslug: [broken\n---\n')
        result = subprocess.run([os.environ['WORKLOG_BIN']+'/compact-kernels.sh'],cwd=self.repo,env=self.env,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr)
        kernels = json.loads((self.repo/'.cache/compact-kernels.json').read_text())
        self.assertEqual(len(kernels),1)
        direct = json.loads(self.call('--for=compact','--format=json').stdout)
        for key in ['slug','next_action','open_items','omitted_items','content_sha256','task_path']:
            self.assertEqual(kernels[0][key],direct[key],key)
        self.assertIn(long_command,kernels[0]['open_items'][0])
        self.assertEqual(len(kernels[0]['open_items']),2)
        self.assertIn('generated_at',kernels[0])
        kernels[0]['expires_at']='2000-01-01T00:00:00+00:00'
        (self.repo/'.cache/compact-kernels.json').write_text(json.dumps(kernels))
        roster = subprocess.run([os.environ['WORKLOG_BIN']+'/kernels-roster.sh'],cwd=self.repo,env=self.env,text=True,capture_output=True)
        self.assertIn('stale',roster.stdout)
        self.assertNotIn('task\tin-progress',roster.stdout)

    def test_compact_markdown_preserves_quoted_spaces(self):
        self.file.write_text("---\nslug: task\nstatus: draft\nnext_action: Check spaces\n---\n## Next\n- [ ] printf '%s' 'a  b'\n")
        self.assertIn("printf '%s' 'a  b'",self.call('--for=compact').stdout)

    def test_markdown_exposes_source_identity_and_freshness(self):
        import hashlib
        from datetime import datetime, timedelta
        out = self.call('--for=compact').stdout
        fields = dict(line.split(': ',1) for line in out.splitlines() if ': ' in line and not line.startswith(' '))
        self.assertEqual(fields['content_sha256'],hashlib.sha256(self.file.read_bytes()).hexdigest())
        generated = datetime.fromisoformat(fields['generated_at'])
        expires = datetime.fromisoformat(fields['expires_at'])
        self.assertIsNotNone(generated.tzinfo)
        self.assertEqual(expires-generated,timedelta(hours=1))

    def test_clock_changes_only_suffix_but_hidden_source_change_invalidates_identity(self):
        import datetime, sys
        sys.path.insert(0,os.environ['WORKLOG_BIN'])
        from _task_context import make_kernel, parse_task_file, kernel_markdown, cache_freshness
        now = datetime.datetime(2026,9,14,tzinfo=datetime.timezone.utc)
        source = self.file.read_text()
        def kernel(text,at):
            fm,body = parse_task_file(text)
            return make_kernel('task',fm,body,text,self.file,now=at)
        first = kernel(source,now)
        later = kernel(source,now+datetime.timedelta(minutes=5))
        for render,marker in [(kernel_markdown,'generated_at:'),(json.dumps,'"generated_at":')]:
            before,after = render(first),render(later)
            self.assertEqual(before.split(marker)[0],after.split(marker)[0])
            self.assertNotEqual(before,after)
        changed = kernel(source.replace('## Context','## Context\nChanged shared decision.'),now)
        self.assertEqual(first['open_items'],changed['open_items'])
        self.assertNotEqual(first['content_sha256'],changed['content_sha256'])
        self.assertEqual(cache_freshness([first],now+datetime.timedelta(hours=1)),'stale')

    def test_numeric_slug_does_not_cause_cache_drift(self):
        self.write(slug=123)
        subprocess.run([os.environ['WORKLOG_BIN']+'/compact-kernels.sh'],cwd=self.repo,env=self.env,check=True,capture_output=True)
        result = subprocess.run([os.environ['WORKLOG_BIN']+'/preamble.sh','--minimal'],cwd=self.repo,env=self.env,check=True,text=True,capture_output=True)
        self.assertIn('# roster-health: fresh kernels=1',result.stdout)
        self.assertNotIn('!! roster-health:',result.stdout)

    def test_malformed_pr_url_is_a_diagnostic(self):
        self.write(pr_repos={7:'org/one'})
        for url in [None,7,[]]:
            payload = json.dumps({'number':7,'state':'OPEN','url':url})
            import shlex
            (self.bin/'gh').write_text("#!/bin/sh\nprintf '%s' "+shlex.quote(payload)+"\n")
            data = json.loads(self.call('--format=json').stdout)
            self.assertEqual(data['prs'],[])
            self.assertEqual(data['pr_diagnostics'][0]['status'],'unavailable')

    def test_query_failures_are_bounded_diagnostics(self):
        import sys
        from unittest import mock
        sys.path.insert(0,os.environ['WORKLOG_BIN'])
        import _context
        for error in [subprocess.TimeoutExpired(['gh'],10), OSError('unavailable')]:
            with mock.patch.object(_context.subprocess,'run',side_effect=error):
                prs, diagnostics = _context.fetch_prs([7],{'pr_repos':{7:'org/one'}},'')
                self.assertEqual(prs,[])
                self.assertEqual(diagnostics[0]['status'],'unavailable')
                self.assertLess(len(json.dumps(diagnostics)),200)

    def test_resume_markdown_bounds_the_body_and_names_the_recovery_path(self):
        # setUp writes a ~27000-character body. An unbounded resume pack pays
        # that cost on every resume, which is the session least able to afford it.
        out = self.call('--tracker=none').stdout
        self.assertIn('## Body',out)
        self.assertIn('## Context',out)          # the head of the body survives
        self.assertLess(len(out.encode()),12000,'resume markdown body is unbounded')
        notice = next((l for l in out.splitlines() if 'omitted' in l and 'Body' not in l),'')
        self.assertIn('characters omitted',notice)
        self.assertIn(str(self.file),notice,'omission notice must name the full-body path')

    def test_short_body_is_not_truncated(self):
        # Guards the cap against firing on every task: a body under the ceiling
        # must arrive whole, with no omission notice.
        self.file.write_text("---\nslug: task\nstatus: draft\nnext_action: Go\n---\n## Context\nshort body\n## Next\n- [ ] one\n")
        out = self.call('--tracker=none').stdout
        self.assertIn('short body',out)
        self.assertNotIn('characters omitted',out)

    def test_invalid_options_fail_before_context(self):
        for args in [('--for=typo',),('--format=typo',),('--tracker=typo',),('--for',)]:
            self.assertEqual(self.call(*args,check=False).returncode,2)

unittest.main()
PY
