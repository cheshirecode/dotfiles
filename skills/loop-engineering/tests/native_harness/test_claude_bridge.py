import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
from unittest import mock

from claude_server import ClaudeServer, operational, initialization_error
from public_verifier_mcp import dispatch


class ClaudeBridgeControls(unittest.TestCase):
    def test_only_empty_named_tool_can_invoke_verifier(self):
        verify=mock.Mock(return_value={'success':True})
        for params in ({'name':'shell','arguments':{}},
                       {'name':'verify_work_order','arguments':{'path':'elsewhere'}},
                       {'name':'verify_work_order','arguments':[]},'wrong'):
            with self.subTest(params=params),self.assertRaises(ValueError):
                dispatch({'method':'tools/call','params':params},verify)
        verify.assert_not_called()
        result=dispatch({'method':'tools/call','params':{'name':'verify_work_order','arguments':{}}},verify)
        self.assertEqual(json.loads(result['content'][0]['text']),{'success':True})
        verify.assert_called_once_with()

    def test_stdio_round_trip_and_http_boundary(self):
        with tempfile.TemporaryDirectory() as temp:
            server=ClaudeServer(Path(temp)/'agent',model='claude-fable-5-1[1m]')
            verify=mock.Mock(return_value={'success':False,'checks':[{'name':'controlled-failure','pass':False}]})
            try:
                server.start(temp,public_verifier=verify)
                config=json.loads(server.config.read_text())['mcpServers']['factory']
                url='http://127.0.0.1:'+config['env']['FACTORY_PUBLIC_PORT']+'/verify'
                for headers,body in (({},b'{}'),({'X-Factory-Token':config['env']['FACTORY_PUBLIC_TOKEN']},b'{"path":"x"}')):
                    with self.assertRaises(urllib.error.HTTPError) as caught:
                        urllib.request.urlopen(urllib.request.Request(url,data=body,headers=headers),timeout=5)
                    caught.exception.close()
                verify.assert_not_called()
                requests=[{'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2024-11-05'}},
                    {'jsonrpc':'2.0','method':'notifications/initialized'},
                    {'jsonrpc':'2.0','id':2,'method':'tools/list'},
                    {'jsonrpc':'2.0','id':3,'method':'tools/call','params':{'name':'verify_work_order','arguments':{}}}]
                process=subprocess.run([config['command'],*config['args']],
                    env={**os.environ,**config['env']},input='[]\n'+''.join(json.dumps(r)+'\n' for r in requests),
                    capture_output=True,text=True,timeout=10)
                self.assertEqual(process.returncode,0,process.stderr)
                replies=[json.loads(line) for line in process.stdout.splitlines()]
                self.assertEqual(len(replies),4)
                self.assertEqual(replies[0]['error']['code'],-32700)
                self.assertEqual(replies[1]['result']['protocolVersion'],'2024-11-05')
                self.assertEqual(replies[2]['result']['tools'][0]['name'],'verify_work_order')
                self.assertFalse(json.loads(replies[3]['result']['content'][0]['text'])['success'])
                verify.assert_called_once_with()
            finally:server.close()
            self.assertFalse(server.config.exists())

    def test_excluded_or_wrong_lane_model_rejected_without_run(self):
        with tempfile.TemporaryDirectory() as temp:
            for model in ('gpt-6-astra','gpt-5.6-sol','claude-astra'):
                with self.subTest(model=model),self.assertRaises(ValueError):
                    ClaudeServer(Path(temp)/'never',model=model)
                self.assertFalse((Path(temp)/'never').exists())

    def test_operational_events_remove_reasoning(self):
        event={'type':'assistant','message':{'model':'claude-fable-5-1','content':[
            {'type':'thinking','thinking':'private'}, {'type':'redacted_thinking','data':'private'},
            {'type':'text','text':'visible'}]}}
        self.assertEqual(operational(event)['message']['content'],[{'type':'text','text':'visible'}])

    def test_native_init_requires_correct_model_and_registered_verifier(self):
        event={'type':'system','subtype':'init','model':'claude-fable-5-1','tools':['Edit']}
        self.assertIn('verifier absent',initialization_error(event,'claude-fable-5-1[1m]'))
        event['tools'].append('mcp__factory__verify_work_order')
        self.assertIsNone(initialization_error(event,'claude-fable-5-1[1m]'))
        event['model']='gpt-6-astra'
        self.assertEqual(initialization_error(event,'claude-fable-5-1[1m]'),'Unexpected initialized model')


if __name__=='__main__':unittest.main()
