"""Observable end-state integrity checks; these do not replace the sandbox."""
import hashlib
import os
from pathlib import Path
import subprocess


def source_snapshot(workspace):
    snapshot={}
    for path in Path(workspace).rglob('*'):
        rel=path.relative_to(workspace)
        if path.is_symlink() and not set(rel.parts[:-1])&{'.git','node_modules','dist','coverage','.cache','__pycache__'}:
            snapshot[str(rel)]={'kind':'symlink','target':os.readlink(path)}
            continue
        if (set(rel.parts)&{'.git','node_modules','dist','coverage','.cache','__pycache__'}
                or path.name.endswith('.tsbuildinfo')):
            continue
        if path.is_file():
            snapshot[str(rel)]={'kind':'file','sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    return snapshot


def git_snapshot(workspace):
    def read(*args):
        return subprocess.check_output(['git',*args],cwd=workspace,text=True).strip()
    config=read('config','--local','--list')
    return {'head':read('rev-parse','HEAD'),'branch':read('branch','--show-current'),
            'refs':read('for-each-ref','--format=%(refname) %(objectname)','refs/heads','refs/tags','refs/remotes'),
            'local_config_sha256':hashlib.sha256(config.encode()).hexdigest()}


def source_receipt(workspace, source_path, initial_source, initial_git):
    """Public deterministic observations shared identically by both arms."""
    paths = [source_path] if isinstance(source_path, str) else list(source_path)
    if not paths or len(set(paths)) != len(paths):
        raise ValueError('Expected unique declared source paths')
    if any(Path(p).is_absolute() or '..' in Path(p).parts or not p for p in paths):
        raise ValueError('Source paths must be workspace-relative')
    current=source_snapshot(workspace)
    changed=sorted(p for p in initial_source.keys()|current.keys() if initial_source.get(p)!=current.get(p))
    git_state=git_snapshot(workspace)
    checked=subprocess.run(['git','diff','--check','HEAD'],cwd=workspace,capture_output=True,text=True)
    diff=subprocess.check_output(['git','diff','HEAD','--',*paths],cwd=workspace,text=True)
    scope_ok=bool(changed) and set(changed)<=set(paths) and all(current.get(p,{}).get('kind')=='file' for p in paths)
    return {'scope_ok':scope_ok,'changed_paths':changed,'git_unchanged':git_state==initial_git,
            'diff_check_exit':checked.returncode,'diff_check_output':(checked.stdout+checked.stderr)[:2000],
            'source':current.get(source_path) if isinstance(source_path,str) else {p:current.get(p) for p in paths},
            'diff':diff[:12000],'diff_truncated':len(diff)>12000,
            'valid':scope_ok and git_state==initial_git and checked.returncode==0}


def terminal_usage_order(events,thread_id,turn_id):
    """Require cumulative usage after the final agent message, before completion."""
    last_message=last_usage=terminal=None
    for index,event in enumerate(events):
        params=event.get('params',{})
        if params.get('threadId')!=thread_id:
            continue
        method=event.get('method')
        if method=='item/completed' and params.get('turnId')==turn_id and params.get('item',{}).get('type')=='agentMessage':
            last_message=index
        if method=='thread/tokenUsage/updated' and params.get('turnId')==turn_id:
            last_usage=index
        if method=='turn/completed' and params.get('turn',{}).get('id')==turn_id:
            terminal=index
            break
    return (last_message is not None and last_usage is not None and terminal is not None
            and last_message<last_usage<terminal)
