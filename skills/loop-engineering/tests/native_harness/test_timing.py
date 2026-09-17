"""Controls reproduce the observed clock gap, including the actual turn driver."""
from pathlib import Path
import tempfile
import unittest
from unittest import mock
from app_server import AppServer
from timing import observe


class TimingControls(unittest.TestCase):
    def test_suspend_shaped_gap_is_not_valid_savings(self):
        with mock.patch('timing.time.time',return_value=1342),mock.patch('timing.time.monotonic',return_value=45):
            result=observe(0,0,600)
        self.assertFalse(result['timing_valid'])
        self.assertFalse(result['within_ceiling'])
        self.assertEqual(result['wall_seconds'],1342)
        self.assertEqual(result['monotonic_seconds'],45)

    def test_normal_clocks_valid_but_late_completion_not_timely(self):
        with mock.patch('timing.time.time',return_value=601),mock.patch('timing.time.monotonic',return_value=601):
            result=observe(0,0,600)
        self.assertTrue(result['timing_valid'])
        self.assertFalse(result['within_ceiling'])

    def test_driver_interrupts_on_wall_deadline_when_monotonic_clock_stalls(self):
        with tempfile.TemporaryDirectory() as temp:
            client=object.__new__(AppServer)
            client.output=Path(temp);client.usage={};client.notifications=[]
            client.thread_id='owned';client.usage_errors=[];client.latest_usage_turn=None
            clocks={'wall':1000,'mono':100};calls=[]
            def request(method,params):
                calls.append(method)
                if method=='turn/start':return {'turn':{'id':'one'}}
                if method=='turn/interrupt':
                    client.notifications.append({'method':'turn/completed','params':{'threadId':'owned','turn':{'id':'one','status':'interrupted'}}})
                    return {}
                raise AssertionError(method)
            def receive(timeout):
                clocks['wall']+=700;clocks['mono']+=.01
            client.request=request;client.receive=receive
            with mock.patch('app_server.time.time',side_effect=lambda:clocks['wall']),mock.patch('app_server.time.monotonic',side_effect=lambda:clocks['mono']):
                result=client.turn('controlled',seconds=600)
            self.assertEqual(calls,['turn/start','turn/interrupt'])
            self.assertEqual(result['status'],'interrupted')
            self.assertFalse(result['timing']['timing_valid'])
            self.assertFalse(result['timing']['within_ceiling'])
            self.assertFalse(result['usage_complete'])


if __name__=='__main__':unittest.main()
