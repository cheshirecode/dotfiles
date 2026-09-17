"""Reconcile OpenCode step receipts with exported assistant-message metadata.

Calibrated initially on OpenRouter GLM 5.3 Flash. Unsupported bucket relationships
fail closed; this is not a claim that every provider uses the same token schema.
"""
from harness_usage import integer, money, result


def normalize_opencode(events,exported,exit_code,requested_model):
    out=result('opencode')
    try:
        provider,model=requested_model.split('/',1)
        if not provider or not model or 'astra' in model.casefold():raise ValueError('Invalid requested model')
        session=exported.get('session_id')
        if not session or {e.get('sessionID') for e in events if e.get('sessionID')}!={session}:
            raise ValueError('Missing or mixed session receipts')
        assistants=exported.get('assistant_messages')
        if not isinstance(assistants,list) or not assistants:raise ValueError('Missing exported assistant metadata')
        messages={}
        for info in assistants:
            identity=info.get('id')
            if not identity or identity in messages:raise ValueError('Missing or duplicate assistant identity')
            if info.get('providerID')!=provider or info.get('modelID')!=model:
                raise ValueError('Unexpected or excluded resolved model')
            messages[identity]=info
        out['model_valid']=True
        unique={};steps=[]
        for event in events:
            if event.get('type')!='step_finish':continue
            part=event.get('part',{});identity=part.get('id')
            if not identity:raise ValueError('Missing step identity')
            if identity in unique:
                if unique[identity]!=event:raise ValueError('Conflicting duplicate step receipt')
                continue
            if part.get('sessionID')!=session:raise ValueError('Step belongs to a different session')
            unique[identity]=event;steps.append(part)
        if not steps:raise ValueError('Missing completed step usage')
        by_message={}
        totals={'uncached_input':0,'cache_read_input':0,'cache_write_input':0,'output':0,'reasoning':0,'reported_tokens':0,'reported_cost_usd':0}
        for step in steps:
            message=step.get('messageID')
            if message not in messages or message in by_message:
                raise ValueError('Step-to-assistant mapping is missing or ambiguous')
            info=messages[message]
            if step.get('tokens')!=info.get('tokens') or step.get('reason')!=info.get('finish'):
                raise ValueError('Stream and export usage or completion disagree')
            cost=money(step.get('cost'),'step.cost')
            if abs(cost-money(info.get('cost'),'export.cost'))>1e-9:raise ValueError('Stream and export costs disagree')
            tokens=step.get('tokens') or {};cache=tokens.get('cache') or {}
            counts={'uncached_input':integer(tokens.get('input'),'input'),
                'cache_read_input':integer(cache.get('read'),'cache.read'),
                'cache_write_input':integer(cache.get('write'),'cache.write'),
                'output':integer(tokens.get('output'),'output'),
                'reasoning':integer(tokens.get('reasoning'),'reasoning')}
            total=integer(tokens.get('total'),'total')
            if total!=sum(counts.values()):raise ValueError('Unsupported or inconsistent token bucket relationship')
            counts.update(reported_tokens=total,reported_cost_usd=cost)
            by_message[message]=counts
            for key,value in counts.items():totals[key]+=value
        out['models'][requested_model]=totals
        out['reported_tokens']=totals['reported_tokens'];out['reported_cost_usd']=totals['reported_cost_usd']
        out['cost_basis']='harness reported estimate; not an invoice'
        out['terminal_session']=session
        complete_messages=set(by_message)==set(messages)
        complete_starts={e.get('part',{}).get('messageID') for e in events if e.get('type')=='step_start'}==set(messages)
        reasons_valid=all(s.get('reason')=='tool-calls' for s in steps[:-1]) and steps[-1].get('reason')=='stop'
        out['usage_complete']=(exit_code==0 and exported.get('export_exit')==0 and complete_messages
            and complete_starts and reasons_valid and not any(e.get('type')=='error' for e in events))
        if not out['usage_complete']:out['errors'].append('Incomplete or failed turn; retain observed usage as partial')
    except (ValueError,TypeError,AttributeError,KeyError) as error:
        out['errors'].append(str(error));out['usage_complete']=False
    return out
