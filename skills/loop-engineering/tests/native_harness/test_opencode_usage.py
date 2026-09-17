import copy
import unittest

from opencode_usage import normalize_opencode


MODEL='openrouter/z-ai/glm-5.3-flash'


def receipts():
    tokens={'total':12178,'input':12157,'output':5,'reasoning':16,'cache':{'read':0,'write':0}}
    events=[{'type':'step_start','sessionID':'s','part':{'messageID':'m'}},
        {'type':'step_finish','sessionID':'s','part':{'id':'p','sessionID':'s','messageID':'m',
            'reason':'stop','tokens':tokens,'cost':.00110043}}]
    exported={'session_id':'s','export_exit':0,'assistant_messages':[{'id':'m','providerID':'openrouter',
        'modelID':'z-ai/glm-5.3-flash','tokens':copy.deepcopy(tokens),'cost':.00110043,'finish':'stop'}]}
    return events,exported


class OpenCodeUsageControls(unittest.TestCase):
    def test_observed_provider_mismatch_is_not_repaired_into_success(self):
        events,exported=receipts()
        tokens={'total':4605,'input':4526,'output':0,'reasoning':88,'cache':{'read':0,'write':0}}
        events[-1]['part']['tokens']=tokens
        exported['assistant_messages'][0]['tokens']=copy.deepcopy(tokens)
        out=normalize_opencode(events,exported,0,MODEL)
        self.assertFalse(out['usage_complete']);self.assertIsNone(out['reported_tokens'])
        self.assertIn('Unsupported or inconsistent token bucket relationship',out['errors'])

    def test_separate_reasoning_tokens_are_counted_once(self):
        events,exported=receipts();out=normalize_opencode(events,exported,0,MODEL)
        self.assertTrue(out['usage_complete'],out['errors'])
        self.assertEqual(out['reported_tokens'],12178)
        self.assertEqual(out['models'][MODEL]['reasoning'],16)
        self.assertFalse(out['billing_complete'])

    def test_duplicate_stream_receipt_not_double_counted(self):
        events,exported=receipts();events.append(copy.deepcopy(events[-1]))
        self.assertEqual(normalize_opencode(events,exported,0,MODEL)['reported_tokens'],12178)
        events[-1]['part']['cost']=2
        self.assertFalse(normalize_opencode(events,exported,0,MODEL)['usage_complete'])

    def test_mismatched_or_missing_receipts_cannot_pass(self):
        for mutation in ('model','provider','session','missing_reasoning','total','cost','duplicate_assistant','missing_start'):
            with self.subTest(mutation=mutation):
                events,exported=receipts();info=exported['assistant_messages'][0]
                if mutation=='model':info['modelID']='gpt-6-astra'
                elif mutation=='provider':info['providerID']='other'
                elif mutation=='session':events[0]['sessionID']='other'
                elif mutation=='missing_reasoning':
                    del events[-1]['part']['tokens']['reasoning'];del info['tokens']['reasoning']
                elif mutation=='total':
                    events[-1]['part']['tokens']['total']-=16;info['tokens']['total']-=16
                elif mutation=='cost':info['cost']=0
                elif mutation=='duplicate_assistant':exported['assistant_messages'].append(copy.deepcopy(info))
                else:events.pop(0)
                out=normalize_opencode(events,exported,0,MODEL)
                self.assertFalse(out['usage_complete'],mutation)
                self.assertTrue(out['errors'])

    def test_interrupted_usage_is_partial_and_absence_is_unknown(self):
        events,exported=receipts();out=normalize_opencode(events,exported,130,MODEL)
        self.assertFalse(out['usage_complete']);self.assertEqual(out['reported_tokens'],12178)
        out=normalize_opencode([],{},1,MODEL)
        self.assertFalse(out['usage_complete']);self.assertIsNone(out['reported_tokens'])
        self.assertIsNone(out['reported_cost_usd'])

    def test_all_steps_and_exported_messages_must_reconcile(self):
        events,exported=receipts();second=copy.deepcopy(events);info=copy.deepcopy(exported['assistant_messages'][0])
        second[0]['part']['messageID']='m2'
        second[1]['part'].update(id='p2',messageID='m2')
        info['id']='m2'
        events[-1]['part']['reason']='tool-calls';exported['assistant_messages'][0]['finish']='tool-calls'
        events+=second;exported['assistant_messages'].append(info)
        out=normalize_opencode(events,exported,0,MODEL)
        self.assertTrue(out['usage_complete'],out['errors']);self.assertEqual(out['reported_tokens'],24356)
        del events[1]
        out=normalize_opencode(events,exported,0,MODEL)
        self.assertFalse(out['usage_complete']);self.assertEqual(out['reported_tokens'],12178)


if __name__=='__main__':unittest.main()
