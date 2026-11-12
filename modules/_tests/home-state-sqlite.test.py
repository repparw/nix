
from contextlib import ExitStack
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest

HANDLER = Path(sys.argv.pop(1))


class HomeStateSQLite(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.home = self.root / "home"
        self.stage = self.root / "stage"
        self.home.mkdir()
        self.stage.mkdir()
        self.connections = ExitStack()
        self.addCleanup(self.connections.close)

    def add_database(self, relative, value):
        source = self.home / relative
        source.parent.mkdir(parents=True, exist_ok=True)
        db = sqlite3.connect(source)
        self.connections.callback(db.close)
        self.assertEqual(db.execute("PRAGMA journal_mode=WAL").fetchone(), ("wal",))
        db.execute("CREATE TABLE session (value TEXT)")
        db.execute("INSERT INTO session VALUES (?)", (value,))
        db.commit()
        self.assertTrue(Path(str(source) + "-wal").exists())
        staged = self.stage / relative
        staged.parent.mkdir(parents=True, exist_ok=True)
        for suffix in ("", "-wal", "-shm"):
            shutil.copy2(str(source) + suffix, str(staged) + suffix)
        os.chmod(staged, 0o600)
        return staged

    def run_handler(self, success=True):
        result = subprocess.run([sys.executable, str(HANDLER), str(self.home), str(self.stage)],
                                capture_output=True, text=True, timeout=60)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_detects_databases_without_extension_and_committed_wal(self):
        paths = [
            (".local/share/opencode/opencode.db", "opencode"),
            (".config/codex/goals_1.sqlite", "codex"),
            (".config/net.imput.helium/Default/Web Data", "helium"),
        ]
        for path, value in paths:
            self.add_database(path, value)
        regular = self.stage / ".config/opencode/plugins/local.ts"
        regular.parent.mkdir(parents=True)
        regular.write_text("export default {}\n")
        (self.home / ".config/opencode/plugins").mkdir(parents=True)
        outside = self.root / "outside"
        outside.write_text("external")
        (regular.parent / "shortcut").symlink_to(outside)
        result = self.run_handler()
        self.assertIn("snapshotted 3 SQLite databases", result.stderr)
        for path, value in paths:
            staged = self.stage / path
            with sqlite3.connect(staged) as snapshot:
                self.assertEqual(snapshot.execute("SELECT value FROM session").fetchall(), [(value,)])
                self.assertEqual(snapshot.execute("PRAGMA integrity_check").fetchall(), [("ok",)])
            self.assertEqual(staged.stat().st_mode & 0o777, 0o600)
            for suffix in ("-wal", "-shm"):
                self.assertFalse(Path(str(staged) + suffix).exists())
        self.assertEqual(regular.read_text(), "export default {}\n")
        self.assertTrue((regular.parent / "shortcut").is_symlink())
        self.assertEqual(outside.read_text(), "external")

    def test_changed_or_corrupt_source_fails_instead_of_copying(self):
        staged = self.add_database(".local/share/opencode/opencode.db", "session")
        (self.home / ".local/share/opencode/opencode.db").rename(self.root / "removed.db")
        self.run_handler(success=False)
        self.assertTrue(staged.exists())


if __name__ == "__main__":
    unittest.main()
