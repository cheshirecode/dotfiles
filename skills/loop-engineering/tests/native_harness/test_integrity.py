import tempfile
from pathlib import Path
import subprocess
import unittest
from integrity import source_snapshot, terminal_usage_order, git_snapshot, source_receipt


class IntegrityControls(unittest.TestCase):
    def test_git_edit_does_not_change_identity_but_extra_branch_does(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            def git(*args):subprocess.run(['git',*args],cwd=root,check=True,capture_output=True)
            git('init','-q');(root/'source').write_text('initial')
            git('add','--','source')
            git('-c','user.name=fixture','-c','user.email=fixture@example.invalid','-c','commit.gpgsign=false',
                '-c','core.hooksPath=/dev/null','commit','-qm','fixture')
            before=git_snapshot(root)
            initial_source=source_snapshot(root)
            (root/'source').write_text('edited\n')
            self.assertEqual(git_snapshot(root),before)
            receipt=source_receipt(root,'source',initial_source,before)
            self.assertTrue(receipt['valid'])
            git('add','--','source')
            self.assertIn('+edited',source_receipt(root,'source',initial_source,before)['diff'])
            (root/'unexpected').symlink_to(root,target_is_directory=True)
            self.assertFalse(source_receipt(root,'source',initial_source,before)['scope_ok'])
            (root/'unexpected').unlink()
            (root/'source').write_text('edited \n')
            self.assertFalse(source_receipt(root,'source',initial_source,before)['valid'])
            (root/'source').write_text('edited\n')
            git('branch','unexpected')
            self.assertNotEqual(git_snapshot(root),before)
            self.assertFalse(source_receipt(root,'source',initial_source,before)['git_unchanged'])

    def test_added_directory_symlink_is_observable_without_following_target(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);work=root/'work';work.mkdir();external=root/'external';external.mkdir()
            (external/'private.txt').write_text('outside')
            (work/'source.py').write_text('original')
            before=source_snapshot(work)
            (work/'extra').symlink_to(external,target_is_directory=True)
            after=source_snapshot(work)
            self.assertEqual(set(after)-set(before),{'extra'})
            self.assertEqual(after['extra']['kind'],'symlink')
            self.assertNotIn('extra/private.txt',after)

    def events(self):
        return [
            {'method':'item/completed','params':{'threadId':'owned','turnId':'one','item':{'type':'agentMessage'}}},
            {'method':'thread/tokenUsage/updated','params':{'threadId':'owned','turnId':'one'}},
            {'method':'turn/completed','params':{'threadId':'owned','turn':{'id':'one'}}},
        ]

    def test_final_usage_must_follow_final_message_and_precede_terminal(self):
        events=self.events()
        self.assertTrue(terminal_usage_order(events,'owned','one'))
        self.assertFalse(terminal_usage_order([events[1],events[0],events[2]],'owned','one'))
        self.assertFalse(terminal_usage_order([events[0],events[2],events[1]],'owned','one'))
        self.assertFalse(terminal_usage_order([events[0],events[2]],'owned','one'))
        self.assertFalse(terminal_usage_order(events,'another','one'))
        self.assertFalse(terminal_usage_order(events,'owned','another'))


if __name__=='__main__':unittest.main()
