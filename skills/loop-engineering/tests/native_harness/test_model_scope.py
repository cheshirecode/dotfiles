from pathlib import Path
import tempfile
import unittest
from unittest import mock

from app_server import AppServer,validate_model


class ModelScopeControls(unittest.TestCase):
    def test_missing_or_astra_model_never_starts_process_or_creates_run(self):
        with tempfile.TemporaryDirectory() as temp:
            for model in (None,'','gpt-6-astra','openai/gpt-6-astra','GPT-6-ASTRA'):
                with self.subTest(model=model),mock.patch('app_server.subprocess.Popen') as process:
                    output=Path(temp)/'never-created'
                    with self.assertRaises(ValueError):AppServer(output,model=model)
                    process.assert_not_called();self.assertFalse(output.exists())

    def test_explicit_model_is_forwarded_without_replacement(self):
        with tempfile.TemporaryDirectory() as temp:
            client=object.__new__(AppServer);client.model=validate_model('gpt-5.6-sol');client.output=Path(temp)
            client.request=mock.Mock(return_value={'thread':{'id':'control'},'model':client.model,'modelProvider':'openai'})
            client.start(Path(temp))
            self.assertEqual(client.request.call_args.args[1]['model'],'gpt-5.6-sol')
            self.assertFalse(client.request.call_args.args[1]['allowProviderModelFallback'])

    def test_resolved_model_mismatch_stops_before_any_turn(self):
        with tempfile.TemporaryDirectory() as temp:
            for returned in ('gpt-6-astra','gpt-5.6-terra',None):
                with self.subTest(returned=returned):
                    client=object.__new__(AppServer);client.model='gpt-5.6-sol';client.output=Path(temp)
                    client.request=mock.Mock(return_value={'thread':{'id':'control'},'model':returned,'modelProvider':'openai'})
                    with self.assertRaises((ValueError,RuntimeError)):client.start(Path(temp))
                    self.assertEqual(client.request.call_count,1)
                    self.assertEqual(client.request.call_args.args[0],'thread/start')


if __name__=='__main__':unittest.main()
