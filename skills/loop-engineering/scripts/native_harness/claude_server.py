"""Claude development adapter with retained native usage and a scoped verifier."""
import json
import os
from pathlib import Path
import queue
import signal
import subprocess
import sys
import threading
import time

from app_server import validate_model
from harness_usage import normalize_claude
from timing import observe
from public_verifier_mcp import PublicVerifier


def operational(event):
    """Remove reasoning blocks before writing an event to disk."""
    if event.get('type')=='assistant':
        message=event.get('message',{})
        return {**event,'message':{**message,'content':[b for b in message.get('content',[])
                if b.get('type') not in ('thinking','redacted_thinking') and 'thinking' not in b]}}
    if event.get('type')=='system':
        return {k:event[k] for k in ('type','subtype','session_id','model','tools','permissionMode','claude_code_version','mcp_servers','plugins','skills') if k in event}
    if event.get('type') in ('result','user'):return event
    return {k:event[k] for k in ('type','subtype','error') if k in event}


def initialization_error(event,model):
    if event.get('type')!='system' or event.get('subtype')!='init':return None
    if event.get('model')!=model.removesuffix('[1m]'):return 'Unexpected initialized model'
    if 'mcp__factory__verify_work_order' not in event.get('tools',[]):return 'Required public verifier absent from native tool registry'
    return None


class ClaudeServer:
    def __init__(self,output,*,model):
        self.model=validate_model(model)
        if not model.startswith('claude-'):raise ValueError('Claude lane requires an explicit Claude model ID')
        self.output=Path(output);self.output.mkdir(parents=True,exist_ok=False)
        self.process=None;self.verifier=None;self.stderr=None;self.events=[]

    def start(self,workspace,developer_instructions=None,public_verifier=None):
        self.workspace=Path(workspace).resolve();self.instructions=developer_instructions or ''
        if public_verifier is None:raise ValueError('Claude repair adapter requires an independent public verifier')
        self.verifier=PublicVerifier(public_verifier)
        self.config=self.output/'mcp.json'
        self.config.write_text(json.dumps({'mcpServers':{'factory':{'type':'stdio','command':sys.executable,
            'args':[str(Path(__file__).with_name('public_verifier_mcp.py'))],
            'env':self.verifier.environment}}}))
        self.config.chmod(0o600)

    def turn(self,prompt,seconds=600):
        start=time.monotonic();wall=time.time();events=queue.Queue();stream_errors=[]
        args=['claude','--print','--restricted','--disable-slash-commands','--setting-sources','',
              '--strict-mcp-config','--mcp-config',str(self.config),'--no-session-persistence','--no-chrome',
              '--model',self.model,'--effort','high','--permission-mode','dontAsk',
              '--tools','Read,Edit,Bash,Glob,Grep','--allowed-tools','Read,Edit,Bash,Glob,Grep,mcp__factory__verify_work_order',
              '--append-system-prompt',self.instructions,'--output-format','stream-json','--verbose',prompt]
        self.stderr=(self.output/'stderr.log').open('w')
        self.process=subprocess.Popen(args,cwd=self.workspace,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,
            stderr=self.stderr,text=True,start_new_session=True)
        def read():
            try:
                for line in self.process.stdout:
                    try:events.put(operational(json.loads(line)))
                    except (ValueError,TypeError):stream_errors.append('Invalid JSON event')
            finally:events.put(None)
        reader=threading.Thread(target=read,daemon=True);reader.start()
        interrupted=False;interrupt_at=None;closed=False
        with (self.output/'events.jsonl').open('w') as log:
            while not closed:
                now=time.monotonic()
                if not interrupted and (now-start>=seconds or time.time()-wall>=seconds):
                    self._signal(signal.SIGINT);interrupted=True;interrupt_at=now
                elif interrupted and now-interrupt_at>=10:
                    self._signal(signal.SIGTERM)
                    if now-interrupt_at>=20:self._signal(signal.SIGKILL)
                    if now-interrupt_at>=25:raise TimeoutError('Claude did not close stdout after cancellation')
                try:event=events.get(timeout=.2)
                except queue.Empty:continue
                if event is None:closed=True;continue
                self.events.append(event);log.write(json.dumps(event)+'\n');log.flush()
                init_error=initialization_error(event,self.model)
                if init_error and not interrupted:
                    self._signal(signal.SIGINT);interrupted=True;interrupt_at=now
                    stream_errors.append(init_error)
                actual=event.get('message',{}).get('model') if event.get('type')=='assistant' else None
                if actual and actual!=self.model.removesuffix('[1m]') and not interrupted:
                    self._signal(signal.SIGINT);interrupted=True;interrupt_at=now
                    stream_errors.append('Unexpected assistant model')
        code=self.process.wait(timeout=10);reader.join(timeout=2)
        native=normalize_claude(self.events,code,self.model)
        terminal=next((e for e in reversed(self.events) if e.get('type')=='result'),{})
        completed=(code==0 and not interrupted and terminal.get('subtype')=='success'
                   and terminal.get('is_error') is False and native['model_valid'])
        totals=native['models'];usage=None
        if native['reported_tokens'] is not None:
            usage={'totalTokens':native['reported_tokens'],'inputTokens':sum(v['uncached_input']+v['cache_read_input']+v['cache_write_input'] for v in totals.values()),
                   'outputTokens':sum(v['output'] for v in totals.values()),'cachedInputTokens':sum(v['cache_read_input'] for v in totals.values()),
                   'cacheWriteInputTokens':sum(v['cache_write_input'] for v in totals.values())}
        result={'status':'completed' if completed else 'interrupted' if interrupted else 'failed',
                'timing':observe(wall,start,seconds),'usage_complete':native['usage_complete'] and not stream_errors,
                'usage_delta':usage,'native_usage':native,'exit':code,'interrupt_requested':interrupted,
                'usage_errors':stream_errors+native['errors'],'terminal_usage_order_valid':native['usage_complete']}
        observed_models=sorted({e['message']['model'] for e in self.events
            if e.get('type')=='assistant' and e.get('message',{}).get('model')})
        (self.output/'thread.json').write_text(json.dumps({'model':observed_models[0] if len(observed_models)==1 else None,
            'observed_models':observed_models,
            'requested_model':self.model,'modelProvider':'anthropic','harness':'claude-code',
            'model_valid':native['model_valid'],'session_id':terminal.get('session_id')},indent=2)+'\n')
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
        if self.stderr is not None:self.stderr.close()
        if hasattr(self,'config') and self.config.exists():self.config.unlink()
