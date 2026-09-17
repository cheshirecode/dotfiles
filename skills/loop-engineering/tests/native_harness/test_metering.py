import io
import queue
import unittest

from app_server import AppServer


class MeteringTests(unittest.TestCase):
    def client(self):
        client = object.__new__(AppServer)
        client.inbox = queue.Queue()
        client.events = io.StringIO()
        client.notifications = []
        client.responses = {}
        client.usage = {}
        client.usage_updates = []
        client.usage_errors = []
        client.latest_usage_turn = None
        client.thread_id = 'owned'
        client.public_verifier = None
        return client

    def update(self, client, amount, thread='owned', turn='one'):
        client.inbox.put({'method': 'thread/tokenUsage/updated', 'params': {
            'threadId': thread, 'turnId': turn, 'tokenUsage': {'total': {
                'totalTokens': amount + 2, 'inputTokens': amount,
                'outputTokens': 2, 'cachedInputTokens': 0}}}})
        client.receive(.1)

    def test_duplicate_cumulative_updates_are_not_added(self):
        client = self.client()
        self.update(client, 100)
        self.update(client, 100)
        self.update(client, 140, turn='two')
        self.assertEqual(client.usage['total']['inputTokens'], 140)
        self.assertEqual(client.latest_usage_turn, 'two')
        self.assertEqual(client.usage_errors, [])

    def test_other_thread_usage_cannot_replace_owned_usage(self):
        client = self.client()
        self.update(client, 100)
        self.update(client, 900, thread='other')
        self.assertEqual(client.usage['total']['inputTokens'], 100)
        self.assertTrue(client.usage_errors)

    def test_counter_regression_invalidates_measurement(self):
        client = self.client()
        self.update(client, 100)
        self.update(client, 30)
        self.assertEqual(client.usage['total']['inputTokens'], 100)
        self.assertTrue(client.usage_errors)

    def test_missing_usage_does_not_become_zero(self):
        client = self.client()
        client.inbox.put({'method': 'thread/tokenUsage/updated', 'params': {
            'threadId': 'owned', 'turnId': 'one', 'tokenUsage': {'total': {}}}})
        client.receive(.1)
        self.assertEqual(client.usage, {})
        self.assertIsNone(client.latest_usage_turn)
        self.assertTrue(client.usage_errors)

    def test_public_verifier_is_bound_to_owned_thread_and_empty_arguments(self):
        client = self.client()
        calls, sent = [], []
        client.public_verifier = lambda: calls.append('verified') or {'success': True}
        client.send = sent.append
        for ident, thread, arguments in [(1, 'owned', {}), (2, 'other', {}), (3, 'owned', {'path': '/outside'})]:
            client.inbox.put({'id': ident, 'method': 'item/tool/call', 'params': {
                'threadId': thread, 'turnId': 'one', 'tool': 'verify_work_order',
                'arguments': arguments, 'callId': str(ident)}})
            client.receive(.1)
        self.assertEqual(calls, ['verified'])
        self.assertTrue(sent[0]['result']['success'])
        self.assertIn('error', sent[1])
        self.assertIn('error', sent[2])


if __name__ == '__main__':
    unittest.main()
