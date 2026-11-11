#!/usr/bin/env python3
"""Local transactional ledger; no network, scheduler or repair execution."""
import argparse
import copy
import decimal
import fcntl
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time


def require(condition, message):
    if not condition:
        raise ValueError(message)


def timestamp(value):
    require(isinstance(value, str) and value.count('.') == 1, 'Slack ts must be a decimal string')
    left, right = value.split('.')
    require(left.isdigit() and right.isdigit(), 'Invalid Slack timestamp')
    return decimal.Decimal(value)


def init(config, now):
    for key in ('workspace', 'channel', 'thread_ts', 'scope', 'stop_condition'):
        require(isinstance(config.get(key), str) and config[key].strip(), 'Missing ' + key)
    timestamp(config['thread_ts'])
    for key in ('cadence_seconds', 'max_polls', 'run_seconds'):
        require(type(config.get(key)) is int and config[key] > 0, 'Positive integer required: ' + key)
    permissions = config.get('writes', {})
    require(set(permissions) <= {'reaction', 'post'}, 'Unknown write permission')
    for kind, permission in permissions.items():
        require(isinstance(permission, str) and permission.strip(), 'Record user authorization for ' + kind)
    return dict(version=1, config=config, mode='active', deadline=now + config['run_seconds'],
                polls=0, polling=False, failures=0, retry_at=0, cursor=None,
                messages={}, cases={}, effects={}, history=[])


def runnable(state, now):
    require(state['mode'] == 'active', 'Watch is ' + state['mode'])
    require(now < state['deadline'], 'Run budget expired; explicit new budget needed')


def apply(state, event, now):
    """Return an isolated transaction so any validation failure leaves state untouched."""
    s = copy.deepcopy(state)
    kind = event['type']
    if kind in ('pause', 'stop', 'resume'):
        require(s['mode'] != 'stopped', 'Stopped watch is terminal')
        if kind == 'resume':
            require(now < s['deadline'] and s['polls'] < s['config']['max_polls'], 'Budget exhausted')
        s['mode'] = {'pause': 'paused', 'stop': 'stopped', 'resume': 'active'}[kind]
    elif kind == 'poll-start':
        runnable(s, now)
        require(not s['polling'], 'Reconcile interrupted poll first')
        require(s['polls'] < s['config']['max_polls'], 'Poll budget exhausted')
        require(now >= s['retry_at'], 'Backoff is active')
        s['polls'] += 1
        s['polling'] = True
    elif kind == 'poll-result':
        require(s['polling'], 'No reserved poll')
        require(event.get('complete') is True and event.get('next_cursor') == '', 'Pagination incomplete')
        require(event.get('anchor') == {k: s['config'][k] for k in ('workspace', 'channel', 'thread_ts')}, 'Thread mismatch')
        messages = event['messages']
        require(isinstance(messages, list), 'Messages must be a list')
        seen = set()
        for m in messages:
            ts = m['ts']
            require(timestamp(ts) >= timestamp(s['config']['thread_ts']) and ts not in seen, 'Invalid/duplicate message ts')
            seen.add(ts)
            require(isinstance(m['content'], str), 'Normalized content must be a string')
            digest = hashlib.sha256(m['content'].encode()).hexdigest()
            old = s['messages'].get(ts)
            if old is None or old['revision'] != digest:
                versions = old['versions'] if old else []
                versions = versions + [dict(revision=digest, content=m['content'], observed_at=now)]
                s['messages'][ts] = dict(revision=digest, versions=versions, read=False, disposition=None)
                for case in s['cases'].values():
                    if case['message_ts'] == ts:
                        case['superseded'] = True
        require(s['config']['thread_ts'] in seen, 'Full thread read must include root')
        s['cursor'] = max(seen | ({s['cursor']} if s['cursor'] else set()), key=timestamp)
        s.update(polling=False, failures=0, retry_at=now + s['config']['cadence_seconds'])
    elif kind == 'poll-failed':
        require(s['polling'], 'No reserved poll')
        require(bool(event.get('error')), 'Failure needs reason')
        s['polling'] = False
        s['failures'] += 1
        delay = min(3600, s['config']['cadence_seconds'] * 2 ** min(s['failures'] - 1, 10))
        retry_after = event.get('retry_after_seconds', 0)
        require(type(retry_after) in (int, float) and retry_after >= 0, 'Invalid Retry-After')
        s['retry_at'] = now + max(delay, retry_after)
        if s['failures'] >= 3 and s['mode'] == 'active':
            s['mode'] = 'paused'
    elif kind in ('read', 'case'):
        runnable(s, now)
        m = s['messages'][event['message_ts']]
        require(event['revision'] == m['revision'], 'Stale message revision')
        if kind == 'read':
            m['read'] = True
            m['disposition'] = event.get('disposition')
        else:
            require(m['read'], 'Read message before mapping a case')
            cid = event['id']
            case = s['cases'].get(cid)
            if case is None:
                require(all(isinstance(event.get(k), str) and event[k].strip() for k in ('given', 'when', 'then')), 'Given/When/Then required')
                case = dict(message_ts=event['message_ts'], revision=m['revision'],
                            acceptance={k: event[k] for k in ('given', 'when', 'then')},
                            superseded=False, attempts=[])
                s['cases'][cid] = case
            require(not case['superseded'] and case['revision'] == m['revision'] and case['message_ts'] == event['message_ts'], 'Case belongs to another revision/message')
            stage = event['stage']
            require(stage in ('mapped', 'implemented', 'deployed', 'verified', 'failed'), 'Invalid case stage')
            require(isinstance(event.get('evidence'), str) and event['evidence'].strip(), 'Evidence reference required')
            if stage in ('implemented', 'deployed', 'verified'):
                commit = event.get('commit', '')
                require(len(commit) == 40 and all(c in '0123456789abcdef' for c in commit), 'Full commit required')
            if stage in ('deployed', 'verified'):
                require(event.get('deployed_commit') == event['commit'], 'Preview must match commit')
            if stage == 'verified':
                require(any(a['stage'] == 'deployed' and a.get('commit') == event['commit'] for a in case['attempts']), 'Deployment evidence required before runtime verification')
            case['attempts'].append(dict(event, at=now))
    elif kind == 'effect-intent':
        runnable(s, now)
        effect = event['kind']
        require(effect in s['config'].get('writes', {}), 'Slack write not authorized')
        if effect == 'reaction':
            require(event.get('emoji') == 'eyes', 'Only eyes acknowledgement supported')
            require(event['key'] == 'eyes:' + event['message_ts'], 'Use stable acknowledgement key')
            require(s['messages'][event['message_ts']]['read'], 'Read before acknowledgement')
        if effect == 'post':
            require(isinstance(event.get('text'), str) and event['text'].strip(), 'Persist exact post text')
            require(isinstance(event.get('case_ids'), list) and event['case_ids'], 'Post must name its case batch')
            require(all(cid in s['cases'] and not s['cases'][cid]['superseded'] for cid in event['case_ids']), 'Post references missing/superseded case')
        key = event['key']
        old = s['effects'].get(key)
        require(old is None or old['outcome'] == 'not_sent', 'Effect already done or uncertain; reconcile first')
        s['effects'][key] = dict(intent=event, outcome='uncertain', attempts=(old['attempts'] if old else []) + [dict(event, at=now)])
    elif kind == 'effect-receipt':
        effect = s['effects'][event['key']]
        outcome = event['outcome']
        require(outcome in ('done', 'not_sent', 'uncertain'), 'Invalid receipt')
        require(effect['outcome'] != 'done' or outcome == 'done', 'Cannot undo confirmed write')
        require(bool(event.get('evidence')), 'Receipt needs provider evidence')
        effect.update(outcome=outcome, receipt=event)
    else:
        raise ValueError('Unknown event type')
    s['history'].append(dict(type=kind, at=now, error=event.get('error')))
    return s


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--state', required=True, type=Path, help='Private directory outside Git')
    p.add_argument('command', choices=('init', 'apply', 'show'))
    p.add_argument('--input', type=Path, help='Configuration or event JSON')
    args = p.parse_args()
    root = args.state.expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    require(not any((parent / '.git').exists() for parent in (root, *root.parents)), 'State must be outside Git')
    with (root / 'lock').open('a') as lock:
        os.chmod(root / 'lock', 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = root / 'state.json'
        if args.command == 'init':
            require(not path.exists(), 'Existing watch; resume it')
            state = init(json.loads(args.input.read_text()), time.time())
        else:
            state = json.loads(path.read_text())
            if args.command == 'apply':
                state = apply(state, json.loads(args.input.read_text()), time.time())
        if args.command != 'show':
            fd, name = tempfile.mkstemp(dir=root, prefix='.state-')
            try:
                with os.fdopen(fd, 'w') as output:
                    json.dump(state, output, indent=2)
                    output.write('\n')
                    output.flush()
                    os.fsync(output.fileno())
                os.replace(name, path)
            finally:
                if os.path.exists(name):
                    os.unlink(name)
        print(json.dumps(dict(mode=state['mode'], polls=state['polls'], cursor=state['cursor'],
                              messages=len(state['messages']), cases=len(state['cases']),
                              uncertain_effects=sum(e['outcome'] == 'uncertain' for e in state['effects'].values()),
                              deadline=state['deadline'], retry_at=state['retry_at'], polling=state['polling'])))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError) as error:
        raise SystemExit(str(error))
