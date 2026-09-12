#!/usr/bin/env bash
set -euo pipefail
WORKLOG_BIN="$(cd "$(dirname "$0")/../../bin" && pwd)"
export WORKLOG_BIN
python3 - <<'PY'
import json, os, pathlib, re, subprocess, tempfile, unittest

ROOT = pathlib.Path(os.environ['WORKLOG_BIN']).parents[2]
LOOP = ROOT/'skills/loop-engineering'
GATE = ROOT/'skills/evidence-gate/scripts/evidence_gate.py'
recipe = re.search(r'<!-- executable: whole-project-completion -->\s*```bash\n(.*?)\n```', (LOOP/'references/orchestrator.md').read_text(), re.S).group(1)

class Completion(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.repo = self.root/'vault'
        self.repo.mkdir()
        self.run = self.root/'run'
        self.remote = self.root/'remote.git'
        self.env = {**os.environ, 'WORKLOG_REPO':str(self.repo), 'WORKLOG_LDAP':'tester',
                    'WORKLOG_NO_HOOK':'1', 'WORKLOG_NO_RETRO':'1', 'WORKLOG_NO_TRANSCRIPT':'1',
                    'run_dir':str(self.run), 'program_slug':'program', 'completion_gate':str(self.root/'gate.json'),
                    'LOOP_RUN':str(LOOP/'scripts/loop_run.py'), 'EVIDENCE_GATE':str(GATE)}
        self.env.pop('BASH_ENV',None)
        subprocess.run(['git','init','-q','--bare',str(self.remote)],check=True)
        self.cmd(['git','init','-q'])
        self.cmd(['git','config','user.email','tester@example.com'])
        self.cmd(['git','config','user.name','Tester'])
        self.cmd(['git','remote','add','origin',str(self.remote)])
        self.active = self.repo/'people/tester/active'
        self.active.mkdir(parents=True)
        (self.active/'program.md').write_text('---\nslug: program\nkind: project\nstatus: in-progress\nnext_action: Run project next program\ntasks:\n  - slug: child\n---\n## Context\nProject proof\n## Next\n- [ ] Roll up\n')
        archive = self.active.parent/'archive'
        archive.mkdir()
        (archive/'child.md').write_text('---\nslug: child\nstatus: archived\nparent_slug: program\nnext_action: ""\n---\n## Context\nVerified child\n')
        self.cmd(['git','add','people'])
        self.cmd(['git','commit','-qm','seed'])
        self.cmd(['git','branch','-M','main'])
        self.cmd(['git','push','-qu','origin','main'])
        self.cmd(['python3',self.env['LOOP_RUN'],str(self.run),'--goal','Verified project','--repo',''])
        self.cmd(['python3',str(GATE),'init','--gate',self.env['completion_gate'],'--goal','Child outcome verified','--criterion','outcome=child proof'])
        self.cmd(['python3',str(GATE),'record','--gate',self.env['completion_gate'],'--criterion','outcome','--kind','git','--ref',self.cmd(['git','rev-parse','HEAD']).stdout.strip(),'--result','child proof committed'])

    def cmd(self,args,check=True):
        return subprocess.run(args,cwd=self.repo,env=self.env,text=True,capture_output=True,check=check)

    def execute(self):
        return self.cmd(['/bin/bash','-c','set -e\n'+recipe],False)

    def test_success_archives_pushes_and_stops(self):
        r = self.execute()
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertFalse((self.active/'program.md').exists())
        self.assertTrue((self.active.parent/'archive/program.md').exists())
        self.assertEqual(json.loads((self.run/'loop_state.json').read_text())['terminal_status'],'complete')
        self.assertEqual(self.cmd(['git','rev-parse','HEAD']).stdout.strip(),self.cmd(['git','ls-remote','origin','refs/heads/main']).stdout.split()[0])

    def test_push_failures_never_stop_complete(self):
        for subject in ['checkpoint','archive']:
            with self.subTest(subject=subject):
                hook = self.remote/'hooks/pre-receive'
                check = 'exit 1' if subject == 'checkpoint' else 'if git log -1 --format=%s "$new" | grep -q "^program: archive ("; then exit 1; fi'
                hook.write_text('#!/bin/sh\nwhile read old new ref; do\n  '+check+'\ndone\n')
                self.cmd(['git','-C',str(self.remote),'config','core.hooksPath',str(self.remote/'hooks')])
                hook.chmod(0o755)
                r = self.execute()
                self.assertNotEqual(r.returncode,0,r.stdout)
                self.assertEqual(json.loads((self.run/'loop_state.json').read_text())['terminal_status'],'running')
                # Remove the rejection, synchronize any local checkpoint, then
                # the next subcase can specifically exercise the archive push.
                hook.unlink()
                self.cmd(['git','push','origin','main'])

    def test_orphan_never_completes(self):
        (self.active/'orphan.md').write_text('---\nslug: orphan\nparent_slug: program\nstatus: draft\n---\n')
        r = self.execute()
        self.assertNotEqual(r.returncode,0)
        self.assertEqual(json.loads((self.run/'loop_state.json').read_text())['terminal_status'],'running')

unittest.main()
PY
