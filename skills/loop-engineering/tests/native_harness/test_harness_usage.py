import copy
import unittest

from harness_usage import normalize_claude,normalize_codex


def claude():
    primary={'inputTokens':2,'outputTokens':18,'cacheReadInputTokens':0,'cacheCreationInputTokens':3483,
             'costUSD':.07058,'canonicalModel':'claude-fable-5-1','provider':'firstParty','costBasis':'list'}
    auxiliary={'inputTokens':908,'outputTokens':15,'cacheReadInputTokens':0,'cacheCreationInputTokens':0,
               'costUSD':.000983,'canonicalModel':'claude-haiku-4-5','provider':'firstParty','costBasis':'list'}
    return [{'type':'system','session_id':'owned'},
        {'type':'assistant','message':{'model':'claude-fable-5-1'}},
        {'type':'result','uuid':'one','session_id':'owned','subtype':'success','is_error':False,
         'terminal_reason':'completed','total_cost_usd':.071563,
         'usage':{'input_tokens':2,'output_tokens':18,'cache_read_input_tokens':0,'cache_creation_input_tokens':3483},
         'modelUsage':{'claude-fable-5-1':primary,'claude-haiku-4-5-20251001':auxiliary}}]


class HarnessUsageControls(unittest.TestCase):
    def test_claude_auxiliary_usage_is_included_once(self):
        events=claude();events.append(copy.deepcopy(events[-1]))
        r=normalize_claude(events,0,'claude-fable-5-1[1m]')
        self.assertTrue(r['usage_complete']);self.assertEqual(r['reported_tokens'],4426)
        self.assertEqual(r['auxiliary_models'],['claude-haiku-4-5-20251001'])
        self.assertEqual(r['reported_cost_usd'],.071563);self.assertFalse(r['billing_complete'])

    def test_claude_invalid_receipts_never_become_complete(self):
        for fault in ('no-result','no-model-usage','missing-bucket','boolean-count','negative-count',
                      'wrong-model','mixed-session','cost-disagreement','usage-disagreement','conflicting-duplicate'):
            with self.subTest(fault=fault):
                events=claude();terminal=events[-1]
                if fault=='no-result':events.pop()
                elif fault=='no-model-usage':del terminal['modelUsage']
                elif fault=='missing-bucket':del terminal['modelUsage']['claude-fable-5-1']['cacheCreationInputTokens']
                elif fault=='boolean-count':terminal['modelUsage']['claude-fable-5-1']['inputTokens']=True
                elif fault=='negative-count':terminal['modelUsage']['claude-fable-5-1']['inputTokens']=-1
                elif fault=='wrong-model':events[1]['message']['model']='claude-opus-5'
                elif fault=='mixed-session':events[0]['session_id']='other'
                elif fault=='cost-disagreement':terminal['total_cost_usd']=.0001
                elif fault=='usage-disagreement':terminal['usage']['output_tokens']=1
                elif fault=='conflicting-duplicate':
                    other=copy.deepcopy(terminal);other['total_cost_usd']=0;events.append(other)
                r=normalize_claude(events,0,'claude-fable-5-1');self.assertFalse(r['usage_complete']);self.assertTrue(r['errors'])

    def test_failed_claude_retains_observed_cost(self):
        events=claude();events[-1]['is_error']=True;events[-1]['terminal_reason']='interrupted'
        r=normalize_claude(events,130,'claude-fable-5-1')
        self.assertFalse(r['usage_complete']);self.assertEqual(r['reported_tokens'],4426)
        self.assertEqual(r['reported_cost_usd'],.071563)

    def codex(self):
        return ({'status':'completed','usage_complete':True,'terminal_usage_order_valid':True,'usage_errors':[],
                 'usage_delta':{'totalTokens':19847,'inputTokens':19839,'cachedInputTokens':7040,'cacheWriteInputTokens':0,'outputTokens':8}},
                {'model':'gpt-5.6-sol','modelProvider':'openai'})

    def test_codex_cache_is_a_subset_not_extra_tokens(self):
        turn,thread=self.codex();r=normalize_codex(turn,thread,'gpt-5.6-sol')
        self.assertTrue(r['usage_complete']);self.assertEqual(r['reported_tokens'],19847)
        self.assertEqual(r['models']['gpt-5.6-sol']['uncached_input'],12799)
        self.assertIsNone(r['reported_cost_usd'])

    def test_missing_codex_cache_write_is_unknown_not_zero(self):
        turn,thread=self.codex();del turn['usage_delta']['cacheWriteInputTokens']
        r=normalize_codex(turn,thread,'gpt-5.6-sol')
        self.assertTrue(r['usage_complete']);self.assertFalse(r['cache_bucket_complete'])
        self.assertIsNone(r['models']['gpt-5.6-sol']['uncached_input'])

    def test_codex_bad_totals_and_unexpected_model_are_rejected(self):
        for fault in ('bad-total','bad-cache','missing-usage','astra','interrupted'):
            with self.subTest(fault=fault):
                turn,thread=self.codex()
                if fault=='bad-total':turn['usage_delta']['totalTokens']=1
                elif fault=='bad-cache':turn['usage_delta']['cachedInputTokens']=99999
                elif fault=='missing-usage':turn['usage_delta']={}
                elif fault=='astra':thread['model']='gpt-6-astra'
                else:turn['status']='interrupted'
                r=normalize_codex(turn,thread,'gpt-5.6-sol');self.assertFalse(r['usage_complete']);self.assertTrue(r['errors'])


if __name__=='__main__':unittest.main()
