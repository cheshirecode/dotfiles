from pathlib import Path
import tempfile
import unittest
from unittest import mock

from opencode_server import OpenCodeServer,load_key,metadata,verifier_connected


class OpenCodeAdapterControls(unittest.TestCase):
    def test_preflight_requires_only_the_declared_connected_server(self):
        self.assertTrue(verifier_connected('gdrive disabled\nfactory \x1b[90mconnected'))
        for text in ('factory disconnected','factory failed','factory connected\nother connected','other connected'):
            self.assertFalse(verifier_connected(text))

    def test_reads_only_named_assignment_without_execution(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'fake-secrets'
            path.write_text('OTHER=value\nexport OPENROUTER_API_KEY="fake-$NOT_EXECUTED" # comment\n')
            self.assertEqual(load_key(path),'fake-$NOT_EXECUTED')
            for value in ('OPENROUTER_API_KEY=','OPENROUTER_API_KEY="unterminated','OTHER=value'):
                path.write_text(value)
                with self.assertRaises(ValueError):load_key(path)

    def test_configuration_keeps_key_out_of_args_and_artifacts(self):
        with tempfile.TemporaryDirectory() as temp:
            server=OpenCodeServer(Path(temp)/'agent',model='openrouter/z-ai/glm-5.3-flash')
            probe=mock.Mock(returncode=0,stdout='factory connected\nfake-test-credential',stderr='')
            try:
                with mock.patch('opencode_server.load_key',return_value='fake-test-credential'),mock.patch('opencode_server.subprocess.run',return_value=probe) as run:
                    server.start(temp,public_verifier=lambda:{'success':True})
                args=run.call_args.args[0];env=run.call_args.kwargs['env']
                self.assertNotIn('fake-test-credential',str(args))
                self.assertNotIn('fake-test-credential',env['OPENCODE_CONFIG_CONTENT'])
                self.assertEqual(env['OPENROUTER_API_KEY'],'fake-test-credential')
                for path in server.output.rglob('*'):
                    if path.is_file():self.assertNotIn('fake-test-credential',path.read_text())
            finally:server.close()
            self.assertIsNone(server.key);self.assertEqual(server.env,{})

    def test_metadata_drops_message_content_and_unknown_fields(self):
        data={'messages':[{'info':{'id':'m','role':'assistant','modelID':'model','providerID':'provider',
             'tokens':{'total':1},'sensitive':'not retained'},'parts':[{'type':'reasoning','text':'not retained'}]}]}
        out=metadata(data,'s',0)
        self.assertNotIn('not retained',str(out))
        self.assertEqual(out['assistant_messages'][0]['modelID'],'model')

    def test_wrong_provider_or_excluded_model_rejected_before_key_access(self):
        with tempfile.TemporaryDirectory() as temp,mock.patch('opencode_server.load_key') as read:
            for model in ('openrouter/openai/gpt-6-astra','github-copilot/gpt-5.6-sol'):
                with self.assertRaises(ValueError):OpenCodeServer(Path(temp)/'never',model=model)
            read.assert_not_called();self.assertFalse((Path(temp)/'never').exists())


if __name__=='__main__':unittest.main()
