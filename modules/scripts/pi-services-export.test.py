"""Exercise private exports and rsync's source-error deletion guard."""

import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("export", sys.argv.pop(1))
export = importlib.util.module_from_spec(spec)
spec.loader.exec_module(export)


class ServicesExport(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "services"
        self.state = self.root / "export"
        (self.source / "hass").mkdir(parents=True)
        self.database = sqlite3.connect(self.source / "hass/home-assistant_v2.db")
        self.addCleanup(self.database.close)
        self.database.execute("PRAGMA journal_mode=WAL")
        self.database.execute("CREATE TABLE messages(value TEXT)")
        self.database.execute("INSERT INTO messages VALUES ('committed WAL record')")
        self.database.commit()

    def prepare(self):
        export.prepare(self.source, self.state, os.getuid(), os.getgid())
        return self.state / "current"

    def test_private_readable_export_includes_wal_and_historical_data(self):
        for directory in ['hermes', 'pihole', 'hass-nixos-trial']:
            (self.source / directory).mkdir(mode=0o700)
            (self.source / directory / 'private.conf').write_text('fixture')
        (self.source / 'dns').mkdir()
        for name in ['listener.conf', 'resolved.conf']:
            (self.source / 'dns' / name).symlink_to('/missing-obsolete-config')
        source_mode = (self.source / 'hermes').stat().st_mode
        current = self.prepare()
        with sqlite3.connect(current / 'hass/home-assistant_v2.db') as snapshot:
            self.assertEqual(snapshot.execute('SELECT value FROM messages').fetchall(),
                             [('committed WAL record',)])
            self.assertEqual(snapshot.execute('PRAGMA integrity_check').fetchall(), [('ok',)])
        self.assertFalse((current / 'hass/home-assistant_v2.db-wal').exists())
        self.assertFalse((current / 'dns/listener.conf').exists())
        self.assertFalse((current / 'dns/resolved.conf').exists())
        for directory in ['hermes', 'pihole', 'hass-nixos-trial']:
            path = current / directory / 'private.conf'
            self.assertEqual(path.read_text(), 'fixture')
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.source / 'hermes').stat().st_mode, source_mode)
        self.assertEqual(json.loads((current / '.pi-services-export.json').read_text())['sqlite'],
                         ['hass/home-assistant_v2.db'])
        destination = self.root / 'mirror'
        destination.mkdir()
        result = subprocess.run(['rsync', '-aL', '--delete-after', str(current) + '/', str(destination)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((destination / 'hermes/private.conf').read_text(), 'fixture')

    def test_failed_export_does_not_publish_or_remove_previous_generation(self):
        previous = self.prepare().resolve()
        (self.source / 'escape').symlink_to('/etc/passwd')
        with self.assertRaisesRegex(ValueError, 'escapes permitted source'):
            self.prepare()
        self.assertEqual((self.state / 'current').resolve(), previous)
        self.assertTrue((previous / 'hass/home-assistant_v2.db').is_file())
        self.assertEqual(list(self.state.glob('snapshot-*')), [previous])

    def test_missing_active_database_preserves_previous_export(self):
        previous = self.prepare().resolve()
        self.database.close()
        (self.source / 'hass/home-assistant_v2.db').unlink()
        with self.assertRaisesRegex(ValueError, 'required Home Assistant database'):
            self.prepare()
        self.assertEqual((self.state / 'current').resolve(), previous)

    def test_nonregular_replacement_does_not_block_reader(self):
        fifo = self.source / 'replacement'
        os.mkfifo(fifo)
        code = '''
import importlib.util, os, pathlib, sys
spec = importlib.util.spec_from_file_location('export', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
try:
    module.secure_open(pathlib.Path(sys.argv[2]), os.O_RDONLY)
except ValueError as error:
    assert 'file type changed' in str(error)
else:
    raise AssertionError('nonregular file accepted')
'''
        result = subprocess.run([sys.executable, '-c', code, export.__file__, str(fifo)],
                                capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rsync_source_error_inhibits_deletion(self):
        if os.getuid() == 0:
            self.skipTest('unreadable-file fixture requires an unprivileged process')
        source = self.root / 'unreadable'
        destination = self.root / 'mirror'
        source.mkdir()
        destination.mkdir()
        (destination / 'retain-on-error').write_text('old backup')
        (source / 'blocked').mkdir(mode=0)
        self.addCleanup((source / 'blocked').chmod, 0o700)
        result = subprocess.run(['rsync', '-a', '--delete-after', str(source) + '/', str(destination)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertTrue((destination / 'retain-on-error').exists())
        self.assertIn('skipping file deletion', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
