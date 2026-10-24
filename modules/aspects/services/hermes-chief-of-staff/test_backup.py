"""Recovery checks for an open WAL database and private ordinary state."""

import contextlib
import io
from pathlib import Path
import sqlite3
import tempfile
import unittest

from backup import backup


class BackupTest(unittest.TestCase):
    def test_live_wal_and_private_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "state"
            source.mkdir()
            database = sqlite3.connect(source / "state.db")
            self.addCleanup(database.close)
            database.execute("PRAGMA journal_mode=WAL")
            database.execute("CREATE TABLE decisions (rationale TEXT)")
            database.execute("INSERT INTO decisions VALUES ('preserve originals')")
            database.commit()
            (source / "USER.md").write_text("private fixture")
            (source / "config-link").symlink_to("USER.md")
            destination = root / "backup"
            with contextlib.redirect_stdout(io.StringIO()):
                backup(source, destination)
            self.assertFalse((destination / "state.db-wal").exists())
            with sqlite3.connect(destination / "state.db") as restored:
                self.assertEqual(restored.execute("SELECT * FROM decisions").fetchall(),
                                 [("preserve originals",)])
                self.assertEqual(restored.execute("PRAGMA integrity_check").fetchone(), ("ok",))
            self.assertEqual((destination / "USER.md").read_text(), "private fixture")
            self.assertTrue((destination / "config-link").is_symlink())
            self.assertEqual(destination.stat().st_mode & 0o777, 0o700)
            self.assertEqual((destination / "USER.md").stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                backup(source, destination)
            self.assertEqual(database.execute("SELECT COUNT(*) FROM decisions").fetchone(), (1,))

    def test_rejects_backup_inside_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError):
                backup(root, root / "nested")

    def test_preserves_ordinary_files_with_sidecar_suffixes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "state"
            source.mkdir()
            (source / "notes").write_text("ordinary state")
            for suffix in ("-wal", "-shm", "-journal"):
                (source / ("notes" + suffix)).write_text("unique state")
            destination = root / "backup"
            with contextlib.redirect_stdout(io.StringIO()):
                backup(source, destination)
            for suffix in ("-wal", "-shm", "-journal"):
                self.assertEqual((destination / ("notes" + suffix)).read_text(), "unique state")


if __name__ == "__main__":
    unittest.main()
