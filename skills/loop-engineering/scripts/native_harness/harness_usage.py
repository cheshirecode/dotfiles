"""Normalize observed native receipts without treating missing usage as zero.

These are metering adapters, not execution adapters or acceptance graders.
Claude result.modelUsage includes auxiliary calls absent from result.usage.
Codex inputTokens includes cached input; do not add that subset again.
"""
import math
import re


def integer(value,name):
    if type(value) is not int or value<0:raise ValueError('Missing or invalid '+name)
    return value


def money(value,name):
    if type(value) not in (int,float) or not math.isfinite(value) or value<0:
        raise ValueError('Missing or invalid '+name)
    return value


def result(harness):
    return {'harness':harness,'usage_complete':False,'model_valid':False,
            'reported_tokens':None,'reported_cost_usd':None,'cost_basis':None,
            'models':{},'errors':[],'billing_complete':False}


def normalize_claude(events,exit_code,requested_model):
    out=result('claude-code')
    try:
        expected=re.sub(r'\[1m\]$','',requested_model)
        if not expected or 'astra' in expected.casefold():raise ValueError('Invalid requested model')
        unique={}
        for event in events:
            if event.get('type')!='result':continue
            key=event.get('uuid')
            if not key:raise ValueError('Missing terminal result identity')
            if key in unique and unique[key]!=event:raise ValueError('Conflicting duplicate result')
            unique[key]=event
        if len(unique)!=1:raise ValueError('Need exactly one distinct terminal result')
        terminal=next(iter(unique.values()))
        if not terminal.get('session_id'):raise ValueError('Missing terminal session identity')
        sessions={e['session_id'] for e in events if e.get('session_id')}
        if sessions!={terminal['session_id']}:raise ValueError('Mixed session receipts')
        models=terminal.get('modelUsage')
        if not isinstance(models,dict) or not models:raise ValueError('Missing per-model usage including auxiliary calls')
        for model,usage in models.items():
            if 'astra' in model.casefold():raise ValueError('Excluded model observed')
            counts={name:integer(usage.get(field),model+'.'+field) for name,field in (
                ('uncached_input','inputTokens'),('cache_read_input','cacheReadInputTokens'),
                ('cache_write_input','cacheCreationInputTokens'),('output','outputTokens'))}
            counts['reported_tokens']=sum(counts.values())
            counts['reported_cost_usd']=money(usage.get('costUSD'),model+'.costUSD')
            counts['canonical_model']=usage.get('canonicalModel',model)
            counts['provider']=usage.get('provider')
            counts['cost_basis']=usage.get('costBasis')
            out['models'][model]=counts
        primary=[v for v in out['models'].values() if v['canonical_model']==expected]
        if len(primary)!=1:raise ValueError('Primary model absent or ambiguous in usage')
        actual={e.get('message',{}).get('model') for e in events if e.get('type')=='assistant'}
        if actual!={expected}:raise ValueError('Assistant model differs from requested canonical model')
        out['model_valid']=True
        main_usage=terminal.get('usage',{})
        for name,key in [('uncached_input','input_tokens'),('cache_read_input','cache_read_input_tokens'),
                         ('cache_write_input','cache_creation_input_tokens'),('output','output_tokens')]:
            if integer(main_usage.get(key),'primary.'+key)!=primary[0][name]:
                raise ValueError('Primary and per-model usage disagree: '+key)
        out['reported_tokens']=sum(v['reported_tokens'] for v in out['models'].values())
        out['reported_cost_usd']=money(terminal.get('total_cost_usd'),'total_cost_usd')
        if abs(out['reported_cost_usd']-sum(v['reported_cost_usd'] for v in out['models'].values()))>1e-6:
            raise ValueError('Per-model and total cost estimates disagree')
        out['cost_basis']='harness client estimate; not an invoice'
        out['auxiliary_models']=[k for k,v in out['models'].items() if v['canonical_model']!=expected]
        out['terminal_session']=terminal['session_id']
        out['usage_complete']=(exit_code==0 and terminal.get('subtype')=='success'
            and terminal.get('is_error') is False and terminal.get('terminal_reason')=='completed')
        if not out['usage_complete']:out['errors'].append('No successful terminal receipt; retain observed usage as partial')
    except (ValueError,TypeError,AttributeError) as error:
        out['errors'].append(str(error));out['usage_complete']=False
    return out


def normalize_codex(turn,thread,requested_model):
    out=result('codex')
    try:
        actual=thread.get('model')
        if not actual or 'astra' in actual.casefold() or actual!=requested_model:
            raise ValueError('Unexpected or excluded resolved model')
        if thread.get('modelProvider')!='openai':raise ValueError('Unexpected Codex provider')
        out['model_valid']=True
        u=turn.get('usage_delta') or {}
        total=integer(u.get('totalTokens'),'totalTokens');inputs=integer(u.get('inputTokens'),'inputTokens')
        outputs=integer(u.get('outputTokens'),'outputTokens');cached=integer(u.get('cachedInputTokens'),'cachedInputTokens')
        if total!=inputs+outputs or cached>inputs:raise ValueError('Inconsistent input/output/cache totals')
        writes=integer(u['cacheWriteInputTokens'],'cacheWriteInputTokens') if 'cacheWriteInputTokens' in u else None
        if writes is not None and cached+writes>inputs:raise ValueError('Cache buckets exceed total input')
        out['reported_tokens']=total
        out['models'][actual]={'input_including_cache':inputs,'cache_read_input':cached,
            'cache_write_input':writes,'uncached_input':None if writes is None else inputs-cached-writes,
            'output':outputs,'reported_tokens':total}
        out['cache_bucket_complete']=writes is not None
        out['usage_complete']=(turn.get('usage_complete') is True and turn.get('status')=='completed'
            and turn.get('terminal_usage_order_valid') is True and not turn.get('usage_errors'))
        if not out['usage_complete']:out['errors'].append('Terminal usage missing or incomplete; observed counts are partial')
    except (ValueError,TypeError,AttributeError) as error:
        out['errors'].append(str(error));out['usage_complete']=False
    return out
