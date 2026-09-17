"""OpenRouter-backed OpenCode development adapter; credentials stay in memory."""
import json
import os
from pathlib import Path
import queue
import re
import shlex
import signal
import subprocess
import sys
import threading
import time

from app_server import validate_model
from opencode_usage import normalize_opencode
from public_verifier_mcp import PublicVerifier
from timing import observe


def load_key(path):
    value=None
    for line in Path(path).read_text().splitlines():
        line=line.strip()
        if line.startswith('export '):line=line[7:].lstrip()
        if '=' not in line:continue
        name,raw=line.split('=',1)
        if name.strip()!='OPENROUTER_API_KEY':continue
        try:parts=shlex.split(raw,comments=True)
        except ValueError:raise ValueError('Cannot parse OpenRouter credential assignment') from None
        if len(parts)!=1 or not parts[0]:raise ValueError('OpenRouter credential assignment is empty or malformed')
        value=parts[0]
    if not value:raise ValueError('OpenRouter credential assignment missing')
    return value


def metadata(data,session,exit_code):
    """Only persist selected model/usage fields; never persist the full export."""
    messages=[]
    for message in data.get('messages',[]):
        info=message.get('info',{})
        if info.get('role')=='assistant':
            messages.append({k:info[k] for k in ('id','role','modelID','providerID','finish','cost','tokens') if k in info})
    return {'session_id':session,'export_exit':exit_code,'assistant_messages':messages}


def verifier_connected(text):
    lines=re.sub(r'\x1b\[[0-9;]*m','',text).splitlines()
    connected=[line for line in lines if re.search(r'\bconnected\b',line)]
    return len(connected)==1 and bool(re.search(r'\bfactory\b',connected[0]))


class OpenCodeServer:
    def __init__(self,output,*,model):
        self.model=validate_model(model)
        if not model.startswith('openrouter/'):raise ValueError('Calibrated OpenCode adapter requires an explicit OpenRouter model')
        self.output=Path(output);self.output.mkdir(parents=True,exist_ok=False)
        self.process=None;self.verifier=None;self.events=[];self.key=None

    def start(self,workspace,developer_instructions=None,public_verifier=None):
        if public_verifier is None:raise ValueError('Independent public verifier required')
        self.workspace=Path(workspace).resolve()
        self.key=load_key(Path.home()/'.env.secrets')
        self.verifier=PublicVerifier(public_verifier)
        permission={'*':'deny','read':'allow','edit':'allow','bash':'allow','glob':'allow','grep':'allow','factory_verify_work_order':'allow'}
        config={'model':self.model,'small_model':self.model,'share':'disabled','autoupdate':False,
            'permission':permission,'tools':{'*':False,'read':True,'edit':True,'bash':True,'glob':True,'grep':True,'factory_verify_work_order':True},
            'agent':{'factory':{'mode':'primary','description':'Bounded development work order',
                'prompt':developer_instructions or '', 'permission':permission}},
            'mcp':{'gdrive':{'enabled':False},'factory':{'type':'local','enabled':True,
                'command':[sys.executable,str(Path(__file__).with_name('public_verifier_mcp.py'))],
                'environment':self.verifier.environment}}}
        self.env={**os.environ,'OPENROUTER_API_KEY':self.key,'OPENCODE_CONFIG_CONTENT':json.dumps(config),
            'OPENCODE_DISABLE_CLAUDE_CODE':'true','OPENCODE_DISABLE_AUTOUPDATE':'true',
            'OPENCODE_DISABLE_LSP_DOWNLOAD':'true','OPENCODE_DISABLE_TITLE':'true'}
        # Process environment only: neither config nor credentials are written.
        probe=subprocess.run(['opencode','mcp','list','--pure'],cwd=self.workspace,env=self.env,
            stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=30)
        text=(probe.stdout+probe.stderr).replace(self.key,'[REDACTED]')
        (self.output/'mcp-preflight.txt').write_text(text)
        if probe.returncode or not verifier_connected(text):
            raise RuntimeError('OpenCode verifier did not connect; inspect sanitized MCP preflight')

    def turn(self,prompt,seconds=600):
        start=time.monotonic();wall=time.time();events=queue.Queue();errors=[]
        args=['opencode','run','--pure','--format','json','--model',self.model,'--agent','factory',
            '--title','Factory development work order','--dir',str(self.workspace),prompt]
        self.process=subprocess.Popen(args,cwd=self.workspace,env=self.env,stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
        stderr=[]
        def read():
            try:
                for line in self.process.stdout:
                    try:
                        event=json.loads(line.replace(self.key,'[REDACTED]'))
                        if event.get('type')!='reasoning':events.put(event)
                    except (ValueError,TypeError):errors.append('Invalid JSON event; raw line discarded')
            finally:events.put(None)
        def read_errors():
            for line in self.process.stderr:stderr.append(line.replace(self.key,'[REDACTED]'))
        reader=threading.Thread(target=read,daemon=True);err_reader=threading.Thread(target=read_errors,daemon=True)
        reader.start();err_reader.start();interrupted=False;interrupt_at=None
        with (self.output/'events.jsonl').open('w') as log:
            while True:
                now=time.monotonic()
                if not interrupted and (now-start>=seconds or time.time()-wall>=seconds):
                    self._signal(signal.SIGINT);interrupted=True;interrupt_at=now
                elif interrupted and now-interrupt_at>=10:
                    self._signal(signal.SIGTERM)
                    if now-interrupt_at>=20:self._signal(signal.SIGKILL)
                    if now-interrupt_at>=25:raise TimeoutError('OpenCode stdout did not close after cancellation')
                try:event=events.get(timeout=.2)
                except queue.Empty:continue
                if event is None:break
                self.events.append(event);log.write(json.dumps(event)+'\n');log.flush()
        code=self.process.wait(timeout=10);reader.join(timeout=2);err_reader.join(timeout=2)
        (self.output/'stderr.log').write_text(''.join(stderr))
        sessions={e.get('sessionID') for e in self.events if e.get('sessionID')}
        exported={}
        if len(sessions)==1:
            session=next(iter(sessions))
            probe=subprocess.run(['opencode','export',session,'--pure','--sanitize'],cwd=self.workspace,env=self.env,
                stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=30)
            (self.output/'export-diagnostic.json').write_text(json.dumps({'exit':probe.returncode,
                'stdout_bytes':len(probe.stdout.encode()),'stderr_bytes':len(probe.stderr.encode()),
                'mode':'sanitized native export; retain only selected model and usage metadata'},indent=2)+'\n')
            try:exported=metadata(json.loads(probe.stdout.replace(self.key,'[REDACTED]')),session,probe.returncode)
            except (ValueError,TypeError):errors.append('Session export failed; raw output discarded')
        else:errors.append('No unique native session to reconcile')
        (self.output/'resolved-model.json').write_text(json.dumps(exported,indent=2)+'\n')
        native=normalize_opencode(self.events,exported,code,self.model)
        totals=native['models'];usage=None
        if native['reported_tokens'] is not None:
            usage={'totalTokens':native['reported_tokens'],
                'inputTokens':sum(v['uncached_input']+v['cache_read_input']+v['cache_write_input'] for v in totals.values()),
                'outputTokens':sum(v['output']+v['reasoning'] for v in totals.values()),
                'cachedInputTokens':sum(v['cache_read_input'] for v in totals.values()),
                'cacheWriteInputTokens':sum(v['cache_write_input'] for v in totals.values())}
        complete=native['usage_complete'] and not interrupted and not errors
        result={'status':'completed' if complete else 'interrupted' if interrupted else 'failed',
            'timing':observe(wall,start,seconds),'usage_complete':complete,'usage_delta':usage,
            'native_usage':native,'exit':code,'interrupt_requested':interrupted,'usage_errors':errors+native['errors'],
            'terminal_usage_order_valid':native['usage_complete']}
        (self.output/'turn.json').write_text(json.dumps(result,indent=2)+'\n')
        return result

    def _signal(self,value):
        if self.process is not None and self.process.poll() is None:
            try:os.killpg(self.process.pid,value)
            except ProcessLookupError:pass

    def close(self):
        if self.process is not None and self.process.poll() is None:
            self._signal(signal.SIGTERM)
            try:self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:self._signal(signal.SIGKILL);self.process.wait(timeout=5)
        if self.verifier is not None:self.verifier.close()
        self.key=None
        if hasattr(self,'env'):self.env.clear()
