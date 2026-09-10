"""Execute the documented manual recipe against a recording Drive stub."""
from pathlib import Path
import json
import os
import re
import shlex
import subprocess
import tempfile
import unittest

SKILL = Path(__file__).resolve().parents[1]


class UploadRecipeTest(unittest.TestCase):
    def test_custom_root_docx_and_quoted_company(self):
        reference = SKILL / 'references/upload.md'
        text = reference.read_text() if reference.exists() else (SKILL / 'SKILL.md').read_text()
        script = re.search(r'```bash\n(.*?)\n```', text, re.S).group(1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / 'custom application files'
            output.mkdir()
            files = ['resume-custom.docx', 'cover-custom.txt', 'keywords-custom.txt']
            for name in files:
                (output / name).write_text('synthetic application')
            commands = root / 'calls.jsonl'
            stub = root / 'gws'
            stub.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ['UPLOAD_CALLS'], 'a') as f:
    f.write(json.dumps(args) + '\\n')
if args[:3] == ['drive', 'files', 'list']:
    print('{"files": [{"id": "existing-folder"}]}')
elif '--upload' in args:
    assert pathlib.Path(args[args.index('--upload')+1]).is_file()
    payload = json.loads(args[args.index('--json')+1])
    assert payload['parents'] == ['existing-folder']
    print('{"id":"uploaded"}')
else:
    raise SystemExit('unexpected call')
''')
            stub.chmod(0o755)
            values = {'COMPANY': "O'Reilly \\ Labs", 'CO': 'example', 'JID': '123',
                      'DATE': '2026-09-10', 'OUT': str(output)}
            for key, value in values.items():
                script = re.sub(r'^'+key+r'=.*$', lambda match: key+'='+shlex.quote(value), script, flags=re.M)
            script = re.sub(r'^FILES=.*$', 'FILES=('+' '.join(shlex.quote(f) for f in files)+')', script, flags=re.M)
            env = dict(os.environ, PATH=str(root)+os.pathsep+os.environ['PATH'], UPLOAD_CALLS=str(commands))
            result = subprocess.run(['bash', '-c', script], cwd=root, env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = [json.loads(line) for line in commands.read_text().splitlines()]
            uploads = [c[c.index('--upload')+1] for c in calls if '--upload' in c]
            self.assertEqual(uploads, [str(output / name) for name in files])
            query = json.loads(calls[0][calls[0].index('--params')+1])['q']
            self.assertIn("O\\'Reilly \\\\ Labs", query)


if __name__ == '__main__':
    unittest.main()
