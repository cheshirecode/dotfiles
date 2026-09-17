"""Small stdio client that preserves usage notifications and cancels gracefully."""
import json
from pathlib import Path
import queue
import subprocess
import threading
import time
from integrity import terminal_usage_order
from timing import observe


def validate_model(model):
    if not isinstance(model,str) or not model.strip():
        raise ValueError('Research requires an explicit non-Astra model; no implicit model default.')
    if 'astra' in model.casefold():
        raise ValueError('Astra is excluded from new research trials by user instruction.')
    return model


class AppServer:
    def __init__(self, output, *, model=None):
        self.model = validate_model(model)
        self.output = Path(output)
        self.output.mkdir(parents=True, exist_ok=False)
        self.stderr = (self.output / 'server.stderr').open('w')
        self.events = (self.output / 'events.jsonl').open('w')
        self.process = subprocess.Popen(
            ['codex', 'app-server', '--stdio'], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=self.stderr, text=True, bufsize=1,
        )
        self.inbox = queue.Queue()
        self.next_id = 0
        self.notifications = []
        self.responses = {}
        self.usage = {}
        self.usage_updates = []
        self.latest_usage_turn = None
        self.usage_errors = []
        self.thread_id = None
        self.public_verifier = None
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        try:
            self.request('initialize', {'clientInfo': {'name': 'factory_proof',
                         'title': 'Factory proof experiment', 'version': '0.1'},
                         'capabilities': {'experimentalApi': True}})
            self.send({'method': 'initialized', 'params': {}})
        except Exception:
            self.close()
            raise

    def _read(self):
        try:
            for line in self.process.stdout:
                self.inbox.put(json.loads(line))
        except Exception as error:
            self.inbox.put({'readerError': str(error)})
        finally:
            self.inbox.put({'readerClosed': True})

    def send(self, message):
        self.process.stdin.write(json.dumps(message) + '\n')
        self.process.stdin.flush()

    def receive(self, timeout):
        message = self.inbox.get(timeout=max(.01, timeout))
        if 'readerError' in message or 'readerClosed' in message:
            raise RuntimeError('App-server stream closed: ' + str(message))
        method = message.get('method', '')
        params = message.get('params', {})
        item = params.get('item', {})
        # Retain operational evidence, not raw reasoning or reasoning summaries.
        if 'reasoning' not in method.lower() and item.get('type') != 'reasoning':
            if method in ('thread/tokenUsage/updated', 'turn/started', 'turn/completed',
                          'item/started', 'item/completed', 'error', 'model/rerouted'):
                self.events.write(json.dumps({'observed_at': time.time(), **message}) + '\n')
                self.events.flush()
        if method == 'thread/tokenUsage/updated':
            if params.get('threadId') != self.thread_id:
                self.usage_errors.append('Usage arrived for another thread')
            else:
                total = params['tokenUsage'].get('total', {})
                required = ('totalTokens', 'inputTokens', 'outputTokens', 'cachedInputTokens')
                if any(type(total.get(k)) is not int or total[k] < 0 for k in required):
                    self.usage_errors.append('Missing or invalid usage counters')
                elif any(total[k] < self.usage.get('total', {}).get(k, 0) for k in required):
                    self.usage_errors.append('Cumulative usage decreased')
                else:
                    self.usage = params['tokenUsage']
                    self.latest_usage_turn = params['turnId']
                    self.usage_updates.append(params)
        if 'id' in message and 'method' not in message:
            self.responses[message['id']] = message
        elif method:
            self.notifications.append(message)
            if 'id' in message:
                if (method == 'item/tool/call' and params.get('tool') == 'verify_work_order'
                        and params.get('threadId') == self.thread_id
                        and self.public_verifier is not None and params.get('arguments') == {}):
                    result = self.public_verifier()
                    self.events.write(json.dumps({'observed_at': time.time(),
                        'method': 'factory/publicCheck', 'result': result}) + '\n')
                    self.events.flush()
                    self.send({'id': message['id'], 'result': {
                        'success': True, 'contentItems': [{'type': 'inputText',
                        'text': json.dumps(result)}]}})
                else:
                    # No implicit approvals or invented answers in experiments.
                    self.send({'id': message['id'], 'error': {
                        'code': -32601, 'message': 'Interactive request unavailable in this experiment'}})
        return message

    def request(self, method, params, timeout=60):
        self.next_id += 1
        ident = self.next_id
        self.send({'id': ident, 'method': method, 'params': params})
        deadline = time.monotonic() + timeout
        while ident not in self.responses:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(method)
            try:
                self.receive(remaining)
            except queue.Empty:
                raise TimeoutError(method) from None
        response = self.responses.pop(ident)
        if 'error' in response:
            raise RuntimeError(method + ': ' + json.dumps(response['error']))
        return response['result']

    def start(self, workspace, developer_instructions=None, public_verifier=None):
        params = {'model': self.model, 'cwd': str(Path(workspace).resolve()),
                  'approvalPolicy': 'never', 'sandbox': 'workspace-write',
                  'ephemeral': True, 'allowProviderModelFallback': False}
        params['developerInstructions'] = (
            'This is an isolated experiment work order. Do not delegate or start '
            'other agents. Stay within the declared work order and write scope.\n'
            + (developer_instructions or ''))
        self.public_verifier = public_verifier
        if public_verifier is not None:
            params['dynamicTools'] = [{'type': 'function', 'name': 'verify_work_order',
                'description': 'Run the declared public acceptance checks. The controller returns runtime findings, source fingerprint, current diff, diff-check result, changed paths and Git identity evidence. Results cover public checks only, not independent final acceptance.',
                'inputSchema': {'type': 'object', 'properties': {}, 'additionalProperties': False}}]
        result = self.request('thread/start', params)
        self.thread_id = result['thread']['id']
        (self.output / 'thread.json').write_text(json.dumps({
            'thread_id': self.thread_id, 'model': result.get('model'),
            'modelProvider': result.get('modelProvider'),
            'sandbox': result.get('sandbox'), 'cwd': str(workspace)}, indent=2) + '\n')
        validate_model(result.get('model'))
        if result.get('model') != self.model:
            raise RuntimeError('Resolved model differs from the explicitly selected research model.')
        return self.thread_id

    def turn(self, prompt, seconds=300, interrupt_on_command=False):
        start = time.monotonic()
        start_wall = time.time()
        prior = dict(self.usage.get('total', {}))
        first_notification = len(self.notifications)
        turn = self.request('turn/start', {'threadId': self.thread_id,
            'input': [{'type': 'text', 'text': prompt}], 'effort': 'high'})['turn']
        turn_id = turn['id']
        interrupted = False
        completion = None
        seen = first_notification
        deadline = start + seconds
        wall_deadline = start_wall + seconds
        while completion is None:
            for message in self.notifications[seen:]:
                params = message.get('params', {})
                if params.get('threadId') != self.thread_id:
                    continue
                if message['method'] == 'turn/completed' and params['turn']['id'] == turn_id:
                    completion = params['turn']
                if (interrupt_on_command and message['method'] == 'item/started'
                        and params.get('item', {}).get('type') == 'commandExecution'):
                    deadline = min(deadline, time.monotonic())
            seen = len(self.notifications)
            if completion is not None:
                break
            expired = time.monotonic() >= deadline or time.time() >= wall_deadline
            if expired and not interrupted:
                self.request('turn/interrupt', {'threadId': self.thread_id, 'turnId': turn_id})
                interrupted = True
                deadline = time.monotonic() + 30
                wall_deadline = time.time() + 30
            elif expired:
                raise TimeoutError('No terminal notification after graceful interrupt')
            try:
                self.receive(min(1, max(.01, deadline - time.monotonic())))
            except queue.Empty:
                continue
        total = self.usage.get('total', {})
        delta = {key: value - prior.get(key, 0) for key, value in total.items()}
        timing = observe(start_wall, start, seconds)
        result = {'turn_id': turn_id, 'status': completion['status'],
                  'seconds': timing['wall_seconds'], 'timing': timing,
                  'interrupt_requested': interrupted, 'usage_total': total,
                  'usage_delta': delta,
                  'usage_complete': (completion['status'] == 'completed'
                                     and self.latest_usage_turn == turn_id
                                     and terminal_usage_order(self.notifications, self.thread_id, turn_id)
                                     and not self.usage_errors),
                  'terminal_usage_order_valid': terminal_usage_order(self.notifications, self.thread_id, turn_id),
                  'usage_errors': list(self.usage_errors),
                  'usage_note': 'Interrupted usage is a lower bound unless independently reconciled.'}
        (self.output / (turn_id + '.json')).write_text(json.dumps(result, indent=2) + '\n')
        return result

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=10)
        self.events.close()
        self.stderr.close()
