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
                      'wrong-model','mixed-session','cost-disagreement','usage-exceeds-per-model','conflicting-duplicate'):
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
                # Terminal above per-model is impossible: modelUsage is the
                # superset. The old fixture lowered it instead, which is the
                # ordinary shape of auxiliary calls on the primary model and
                # must NOT be an error.
                elif fault=='usage-exceeds-per-model':terminal['usage']['output_tokens']=9999
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


def claude_collapsed_auxiliary():
    """The shape a real run produces when the requested model is also the one
    the harness uses for its own auxiliary calls: a single modelUsage entry,
    keyed by the dated alias and carrying the undated canonicalModel, whose
    totals exceed the main-thread usage. Counts are the ones measured from
    Claude Code 2.1.275 on 2026-09-17."""
    return [{'type':'system','session_id':'owned'},
        {'type':'assistant','message':{'model':'claude-haiku-4-5-20251001'}},
        {'type':'result','uuid':'one','session_id':'owned','subtype':'success','is_error':False,
         'terminal_reason':'completed','total_cost_usd':.0295031,
         'usage':{'input_tokens':34,'output_tokens':715,'cache_read_input_tokens':30401,
                  'cache_creation_input_tokens':10932},
         'modelUsage':{'claude-haiku-4-5-20251001':{
             'inputTokens':959,'outputTokens':728,'cacheReadInputTokens':30401,
             'cacheCreationInputTokens':10932,'costUSD':.0295031,
             'canonicalModel':'claude-haiku-4-5','provider':'firstParty','costBasis':'list'}}}]


class CollapsedAuxiliaryControls(unittest.TestCase):
    def test_dated_alias_and_canonical_name_identify_one_model(self):
        # Both spellings name the same model. Accepting only one made every
        # dated model ID unusable: the alias found no primary, the undated
        # name failed the assistant check.
        for requested in ('claude-haiku-4-5-20251001','claude-haiku-4-5'):
            with self.subTest(requested=requested):
                r=normalize_claude(claude_collapsed_auxiliary(),0,requested)
                self.assertTrue(r['model_valid']);self.assertTrue(r['usage_complete'])
                self.assertEqual(r['reported_tokens'],43020)
                self.assertEqual(r['auxiliary_models'],[])

    def test_auxiliary_calls_on_the_primary_model_are_kept_not_an_error(self):
        r=normalize_claude(claude_collapsed_auxiliary(),0,'claude-haiku-4-5-20251001')
        self.assertEqual(r['errors'],[])
        self.assertEqual(r['auxiliary_on_primary_model'],
                         {'uncached_input':925,'cache_read_input':0,'cache_write_input':0,'output':13})

    def test_absent_model_is_still_refused(self):
        # The relaxation must not accept a model that never ran.
        r=normalize_claude(claude_collapsed_auxiliary(),0,'claude-opus-5')
        self.assertFalse(r['model_valid']);self.assertFalse(r['usage_complete'])
        self.assertIn('Primary model absent or ambiguous in usage',r['errors'])

    def test_ambiguous_alias_and_unrelated_assistant_are_refused(self):
        for fault in ('ambiguous-alias','wrong-assistant','missing-assistant'):
            with self.subTest(fault=fault):
                events=claude_collapsed_auxiliary()
                if fault=='ambiguous-alias':
                    models=events[-1]['modelUsage']
                    models['another-alias']=copy.deepcopy(next(iter(models.values())))
                elif fault=='wrong-assistant':
                    events[1]['message']['model']='claude-opus-5'
                else:
                    events.pop(1)
                r=normalize_claude(events,0,'claude-haiku-4-5')
                self.assertFalse(r['model_valid']);self.assertFalse(r['usage_complete'])
                self.assertTrue(r['errors'])

    def test_main_thread_cannot_exceed_any_per_model_bucket(self):
        for main_key,model_key in (
            ('input_tokens','inputTokens'),('output_tokens','outputTokens'),
            ('cache_read_input_tokens','cacheReadInputTokens'),
            ('cache_creation_input_tokens','cacheCreationInputTokens')):
            with self.subTest(bucket=main_key):
                events=claude_collapsed_auxiliary();terminal=events[-1]
                terminal['usage'][main_key]=next(iter(terminal['modelUsage'].values()))[model_key]+1
                r=normalize_claude(events,0,'claude-haiku-4-5-20251001')
                self.assertFalse(r['usage_complete'])
                self.assertIn('Primary and per-model usage disagree: '+main_key,r['errors'])


if __name__=='__main__':unittest.main()
