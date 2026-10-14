import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import collector

ENTRY = dict(COREDUMP_EXE='/nix/store/build-wpaperd/bin/wpaperd', COREDUMP_SIGNAL='11', COREDUMP_PID='42', COREDUMP_UID='1000', COREDUMP_TIMESTAMP='1791578336000000', _BOOT_ID='a' * 32, COREDUMP_USER_UNIT='wpaperd.service', __CURSOR='cursor1')


class CollectorTests(unittest.TestCase):
    def test_occurrence_identity_and_stable_frames(self):
        first = collector.event_from(ENTRY, 'alpha', '')
        other = collector.event_from(dict(ENTRY, COREDUMP_PID='43'), 'alpha', '')
        self.assertNotEqual(first['event_id'], other['event_id'])
        self.assertEqual(collector.frame_signature('#0 0xabcd func (lib.so + 0x123)'), 'func (lib.so)')
        self.assertEqual(collector.frame_signature('#0 0x9876 func (lib.so + 0x999)'), 'func (lib.so)')
        self.assertNotIn('SECRET', collector.frame_signature('Environment: SECRET=hidden\n#0 0x123 func'))

    def test_failed_delivery_keeps_event_and_success_records_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            outbox = state / 'coredumps-outbox'
            outbox.mkdir()
            (state / 'coredumps-seen').mkdir()
            event = collector.event_from(ENTRY, 'alpha', '')
            path = outbox / (event['event_id'] + '.json')
            collector.atomic_json(path, event)
            with patch('collector.subprocess.run') as run:
                run.return_value.returncode = 255
                with self.assertRaisesRegex(RuntimeError, 'retained'):
                    collector.deliver(outbox, 'root@host', '/identity')
                self.assertTrue(path.exists())
                run.return_value.returncode = 0
                run.return_value.stdout = json.dumps({'event_id': 'wrong'})
                with self.assertRaisesRegex(RuntimeError, 'ACK mismatch'):
                    collector.deliver(outbox, 'root@host', '/identity')
                self.assertTrue(path.exists())
                run.return_value.stdout = json.dumps({'event_id': event['event_id']})
                collector.deliver(outbox, 'root@host', '/identity')
                self.assertFalse(path.exists())
                self.assertTrue((state / 'coredumps-seen' / path.name).exists())
                self.assertEqual(run.call_args.args[0][-1], '/run/current-system/sw/bin/hermes-crash-ingest')

    def test_journal_cursor_committed_after_durable_spool(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            (state / 'coredumps-outbox').mkdir()
            (state / 'coredumps-seen').mkdir()
            with patch('collector.subprocess.Popen') as popen, patch('collector.subprocess.run') as info:
                popen.return_value.stdout = [json.dumps(ENTRY)]
                popen.return_value.wait.return_value = 0
                popen.return_value.poll.return_value = 0
                info.return_value.stdout = '#0 0x123 func (lib.so + 0x345)'
                collector.collect(state, 'alpha', [])
                self.assertEqual(json.loads((state / 'coredumps-cursor.json').read_text()), {'cursor': 'cursor1'})
                queued = list((state / 'coredumps-outbox').glob('*.json'))
                self.assertEqual(len(queued), 1)
                event = json.loads(queued[0].read_text())
                self.assertEqual(event['frame_signature'], 'func (lib.so)')
                # A replay cannot replace the durable payload with a now-missing stack.
                info.return_value.stdout = ''
                collector.collect(state, 'alpha', [])
                self.assertEqual(json.loads(queued[0].read_text()), event)
                self.assertIn('--after-cursor=cursor1', popen.call_args.args[0])

    def test_mute_advances_cursor_without_queueing(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            (state / 'coredumps-outbox').mkdir()
            with patch('collector.subprocess.Popen') as popen:
                popen.return_value.stdout = [json.dumps(ENTRY)]
                popen.return_value.wait.return_value = 0
                popen.return_value.poll.return_value = 0
                collector.collect(state, 'alpha', ['wpaperd'])
                self.assertEqual(list((state / 'coredumps-outbox').iterdir()), [])
                self.assertTrue((state / 'coredumps-cursor.json').exists())


if __name__ == '__main__':
    unittest.main()
