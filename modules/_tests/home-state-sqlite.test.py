
from contextlib import ExitStack
import json
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
        self.previous = self.root / "previous"
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

    def run_handler(self, success=True, selected=None):
        args = [sys.executable, str(HANDLER), str(self.home),
                str(self.stage), str(self.previous)]
        if selected is not None:
            args.append(json.dumps(selected))
        result = subprocess.run(args, capture_output=True, text=True, timeout=60)
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
        self.assertIn("3 SQLite snapshots fresh", result.stderr)
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

    def test_changed_source_is_degraded_not_published_as_raw_sqlite(self):
        staged = self.add_database(".local/share/opencode/opencode.db", "session")
        (self.home / ".local/share/opencode/opencode.db").rename(self.root / "removed.db")
        self.run_handler()
        report = json.loads((self.stage / ".export-status.json").read_text())
        self.assertEqual(report["status"], "degraded")
        self.assertEqual(report["failures"][0]["status"], "missing")
        self.assertFalse(staged.exists())
        self.assertFalse(Path(str(staged) + "-wal").exists())


    def test_held_sqlite_lock_retains_verified_prior_and_retry_recovers(self):
        rel = ".config/net.imput.helium/Default/DIPS"
        staged = self.add_database(rel, "live new")
        healthy = ".local/share/opencode/opencode.db"
        self.add_database(healthy, "healthy")
        note = self.stage / ".config/vesktop/settings.json"
        note.parent.mkdir(parents=True)
        note.write_text('{"theme":"dark"}')
        # The preceding generation contains a self-contained verified copy.
        old = self.previous / rel
        old.parent.mkdir(parents=True)
        with sqlite3.connect(old) as db:
            db.execute("CREATE TABLE session (value TEXT)")
            db.execute("INSERT INTO session VALUES ('prior')")
        (self.previous / ".export-complete").write_text("old")
        os.utime(self.previous / ".export-complete", (1700000000, 1700000000))

        self.connections.close()
        live = sqlite3.connect(self.home / rel)
        self.addCleanup(live.close)
        self.assertEqual(live.execute("PRAGMA journal_mode=DELETE").fetchone(), ("delete",))
        live.execute("BEGIN EXCLUSIVE")
        self.run_handler()
        status = json.loads((self.stage / ".export-status.json").read_text())
        self.assertEqual(status["status"], "degraded")
        self.assertEqual(status["databases"][rel]["status"], "stale")
        self.assertEqual(status["databases"][rel]["verifiedAt"], 1700000000)
        with sqlite3.connect(staged) as db:
            self.assertEqual(db.execute("SELECT value FROM session").fetchall(), [("prior",)])
        self.assertTrue((self.stage / ".sqlite-retry-needed").exists())
        self.assertEqual(note.read_text(), '{"theme":"dark"}')
        with sqlite3.connect(self.stage / healthy) as db:
            self.assertEqual(db.execute("SELECT value FROM session").fetchall(), [("healthy",)])
        healthy_stamp = status["databases"][healthy]["verifiedAt"]

        live.rollback()
        result = subprocess.run([sys.executable, str(HANDLER), "--retry",
                                 str(self.home), str(self.stage)],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        recovered = json.loads((self.stage / ".export-status.json").read_text())
        self.assertEqual(recovered["status"], "degraded")
        self.assertTrue(recovered["recoveryPending"])
        self.assertEqual(recovered["failures"], [])
        self.assertEqual(recovered["databases"][healthy]["verifiedAt"], healthy_stamp)
        with sqlite3.connect(staged) as db:
            self.assertEqual(db.execute("SELECT value FROM session").fetchall(), [("live new",)])
        self.assertFalse((self.stage / ".sqlite-retry-needed").exists())

    def test_invalid_previous_sidecars_are_not_reused(self):
        rel = "browser/DIPS"
        staged = self.add_database(rel, "live")
        old = self.previous / rel
        old.parent.mkdir(parents=True)
        shutil.copy2(staged, old)
        (old.parent / "DIPS-wal").write_bytes(b"unsafe")
        (self.previous / ".export-complete").touch()
        (self.home / rel).unlink()
        self.run_handler()
        status = json.loads((self.stage / ".export-status.json").read_text())
        self.assertEqual(status["databases"][rel]["status"], "missing")
        self.assertFalse(staged.exists())

    def test_previously_tracked_database_missing_from_stage_is_degraded(self):
        rel = ".config/net.imput.helium/Default/DIPS"
        staged = self.add_database(rel, "last good")
        self.connections.close()
        old = self.previous / rel
        old.parent.mkdir(parents=True)
        shutil.copy2(self.home / rel, old)
        (self.previous / ".export-status.json").write_text(json.dumps({
            "schemaVersion": 1, "status": "complete",
            "databases": {rel: {"status": "fresh", "verifiedAt": 1700000000}},
        }))
        staged.unlink()
        (self.home / rel).unlink()
        self.run_handler(selected=[".config/net.imput.helium/"])
        report = json.loads((self.stage / ".export-status.json").read_text())
        self.assertEqual(report["status"], "degraded")
        self.assertEqual(report["databases"][rel]["status"], "stale")
        self.assertEqual(report["databases"][rel]["verifiedAt"], 1700000000)
        with sqlite3.connect(staged) as db:
            self.assertEqual(db.execute("SELECT value FROM session").fetchall(),
                             [("last good",)])

    def test_retired_dips_database_is_not_reintroduced(self):
        rel = ".config/net.imput.helium/Default/DIPS"
        old = self.previous / rel
        old.parent.mkdir(parents=True)
        with sqlite3.connect(old) as db:
            db.execute("CREATE TABLE example (value TEXT)")
            db.execute("INSERT INTO example VALUES ('previous')")

        (self.previous / ".export-status.json").write_text(json.dumps({
            "schemaVersion": 1, "status": "complete",
            "databases": {rel: {"status": "fresh", "verifiedAt": 1700000000}},
        }))
        bookmarks = self.stage / ".config/net.imput.helium/Default/Bookmarks"
        bookmarks.parent.mkdir(parents=True)
        bookmarks.write_text('{"roots":{}}')
        selected = [
            ".config/net.imput.helium/Default/Bookmarks",
            ".config/net.imput.helium/Default/Preferences",
            ".config/net.imput.helium/Default/Sessions/",
            ".config/net.imput.helium/Local State",
        ]
        self.run_handler(selected=selected)
        status = json.loads((self.stage / ".export-status.json").read_text())
        self.assertEqual(status["status"], "complete")
        self.assertEqual(status["databases"], {})
        self.assertEqual(status["failures"], [])
        self.assertFalse((self.stage / rel).exists())
        self.assertEqual(bookmarks.read_text(), '{"roots":{}}')

    def test_publish_atomically_exchanges_generations(self):
        self.previous.mkdir()
        (self.previous / "old").write_text("old")
        (self.stage / "new").write_text("new")
        result = subprocess.run([sys.executable, str(HANDLER), "--publish",
                                 str(self.stage), str(self.previous)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.previous / "new").exists())
        self.assertTrue((self.stage / "old").exists())

if __name__ == "__main__":
    unittest.main()
