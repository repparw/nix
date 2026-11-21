import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

HANDLER = Path(sys.argv.pop(1))


class HomeStateBackup(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.home = self.root / "home"
        self.stage = self.root / "stage"
        self.previous = self.root / "previous"
        self.home.mkdir()
        self.stage.mkdir()
        self.writers = []
        self.addCleanup(lambda: [writer.close() for writer in self.writers])
        self.selected = [
            ".config/net.imput.helium/Default/Bookmarks",
            ".local/share/opencode/",
            "Projects/nix/infra/terraform.tfstate",
        ]
        self.excludes = ["/.local/share/opencode/log/"]

    def write(self, relative, data):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        return path

    def database(self, relative, value):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(path)
        self.writers.append(connection)
        self.assertEqual(connection.execute("PRAGMA journal_mode=WAL").fetchone(), ("wal",))
        connection.execute("CREATE TABLE session (value TEXT)")
        connection.execute("INSERT INTO session VALUES (?)", (value,))
        connection.commit()
        return connection

    def run_export(self, stage=None, previous=None):
        stage = stage or self.stage
        args = [
            sys.executable, str(HANDLER), str(self.home), str(stage),
            str(previous or self.previous), json.dumps(self.selected),
            json.dumps(self.excludes),
        ]
        run = subprocess.run(args, capture_output=True, text=True, timeout=60)
        self.assertEqual(run.returncode, 0, run.stderr)
        return json.loads((stage / ".export-status.json").read_text())

    def listed(self, stage=None):
        stage = stage or self.stage
        return set((stage / ".home-files").read_bytes().strip(b"\0").split(b"\0"))

    def test_ordinary_files_direct_sqlite_snapshot_only(self):
        bookmarks = self.write(".config/net.imput.helium/Default/Bookmarks", '{"roots":{}}')
        tofu = self.write("Projects/nix/infra/terraform.tfstate", '{"serial":1}')
        auth = self.write(".local/share/opencode/auth.json", '{"token":"test"}')
        special = self.write(".local/share/opencode/[test]*.txt", "special")
        excluded = self.write(".local/share/opencode/log/current.log", "log")
        self.write(".config/net.imput.helium/Default/DIPS", "excluded")
        db_path = ".local/share/opencode/opencode.db"
        self.database(db_path, "committed WAL row")

        report = self.run_export()
        self.assertEqual(report["status"], "complete")
        listed = self.listed()
        for path in (bookmarks, tofu, auth, special):
            self.assertIn(os.fsencode(path), listed)
            self.assertFalse((self.stage / path.relative_to(self.home)).exists())
        for path in (excluded, self.home / db_path,
                     self.home / (db_path + "-wal"),
                     self.home / ".config/net.imput.helium/Default/DIPS"):
            self.assertNotIn(os.fsencode(path), listed)
        snapshot = self.stage / db_path
        with sqlite3.connect(snapshot) as db:
            self.assertEqual(db.execute("SELECT value FROM session").fetchall(),
                             [("committed WAL row",)])
            self.assertEqual(db.execute("PRAGMA quick_check").fetchone(), ("ok",))
        self.assertFalse(Path(str(snapshot) + "-wal").exists())
        self.assertTrue((self.stage / ".export-complete").exists())

    def test_locked_db_fallback_and_next_full_export(self):
        db_path = ".local/share/opencode/opencode.db"
        self.database(db_path, "new")
        self.write("Projects/nix/infra/terraform.tfstate", '{"serial":2}')
        old = self.previous / db_path
        old.parent.mkdir(parents=True)
        with sqlite3.connect(old) as db:
            db.execute("CREATE TABLE session (value TEXT)")
            db.execute("INSERT INTO session VALUES ('prior')")
        self.previous.joinpath(".export-status.json").write_text(json.dumps({
            "schemaVersion": 1,
            "databases": {db_path: {"status": "fresh", "verifiedAt": 1700000000}},
        }))
        # Close the WAL writer before acquiring an exclusive lock.
        self.writers[0].close()
        self.writers.clear()
        source = self.home / db_path
        live = sqlite3.connect(source)
        self.assertEqual(live.execute("PRAGMA journal_mode=DELETE").fetchone(), ("delete",))
        live.execute("BEGIN EXCLUSIVE")
        try:
            report = self.run_export()
            self.assertEqual(report["status"], "degraded")
            self.assertEqual(report["databases"][db_path]["status"], "stale")
            self.assertEqual(report["databases"][db_path]["verifiedAt"], 1700000000)
            self.assertFalse((self.stage / ".export-complete").exists())
            with sqlite3.connect(self.stage / db_path) as db:
                self.assertEqual(db.execute("SELECT value FROM session").fetchall(),
                                 [("prior",)])
        finally:
            live.rollback()
            live.close()
        next_stage = self.root / "next"
        next_stage.mkdir()
        fresh = self.run_export(stage=next_stage, previous=self.stage)
        self.assertEqual(fresh["status"], "complete")
        with sqlite3.connect(next_stage / db_path) as db:
            self.assertEqual(db.execute("SELECT value FROM session").fetchall(),
                             [("new",)])
        self.assertTrue((next_stage / ".export-complete").exists())

    def test_intentionally_removed_sqlite_is_not_reintroduced(self):
        rel = ".config/net.imput.helium/Default/DIPS"
        old = self.previous / rel
        old.parent.mkdir(parents=True)
        with sqlite3.connect(old) as db:
            db.execute("CREATE TABLE example (value TEXT)")
        self.previous.joinpath(".export-status.json").write_text(json.dumps({
            "schemaVersion": 1,
            "databases": {rel: {"status": "fresh", "verifiedAt": 1700000000}},
        }))
        bookmarks = self.write(".config/net.imput.helium/Default/Bookmarks", "{}")
        report = self.run_export()
        self.assertEqual(report["status"], "complete")
        self.assertEqual(report["databases"], {})
        self.assertFalse((self.stage / rel).exists())
        self.assertIn(os.fsencode(bookmarks), self.listed())

    def test_retired_database_does_not_degrade_or_backup_orphaned_wal(self):
        rel = ".local/share/opencode/retired.db"
        old = self.previous / rel
        old.parent.mkdir(parents=True)
        with sqlite3.connect(old) as db:
            db.execute("CREATE TABLE example(value TEXT)")
        (self.previous / ".export-status.json").write_text(json.dumps({
            "schemaVersion": 1,
            "databases": {rel: {"status": "fresh", "verifiedAt": 1700000000}},
        }))
        wal = self.write(rel + "-wal", "orphaned WAL")
        report = self.run_export()
        self.assertEqual(report["status"], "complete")
        self.assertEqual(report["databases"], {})
        self.assertNotIn(os.fsencode(wal), self.listed())
        self.assertFalse((self.stage / rel).exists())

    def test_corrupt_sqlite_extensions_are_not_backed_up_raw(self):
        broken = [self.write(f".local/share/opencode/broken{suffix}", "bad header")
                  for suffix in (".db", ".sqlite", ".sqlite3")]
        report = self.run_export()
        self.assertEqual(report["status"], "degraded")
        self.assertEqual(len(report["failures"]), len(broken))
        for path in broken:
            self.assertEqual(report["databases"][str(path.relative_to(self.home))]["status"],
                             "missing")
            self.assertNotIn(os.fsencode(path), self.listed())
            self.assertFalse((self.stage / path.relative_to(self.home)).exists())

    def test_corrupt_known_extensionless_database_uses_verified_fallback(self):
        rel = ".local/share/opencode/session-store"
        bad = self.write(rel, "bad header")
        old = self.previous / rel
        old.parent.mkdir(parents=True)
        with sqlite3.connect(old) as db:
            db.execute("CREATE TABLE session(value TEXT)")
            db.execute("INSERT INTO session VALUES ('prior')")
        (self.previous / ".export-status.json").write_text(json.dumps({
            "schemaVersion": 1,
            "databases": {rel: {"status": "fresh", "verifiedAt": 1700000000}},
        }))
        report = self.run_export()
        self.assertEqual(report["status"], "degraded")
        self.assertEqual(report["databases"][rel]["status"], "stale")
        self.assertNotIn(os.fsencode(bad), self.listed())
        with sqlite3.connect(self.stage / rel) as db:
            self.assertEqual(db.execute("SELECT value FROM session").fetchone(), ("prior",))

    def test_publish_swaps_small_export(self):
        self.previous.mkdir()
        (self.previous / "old").write_text("old")
        (self.stage / "new").write_text("new")
        run = subprocess.run([
            sys.executable, str(HANDLER), "--publish",
            str(self.stage), str(self.previous),
        ], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertTrue((self.previous / "new").exists())
        self.assertTrue((self.stage / "old").exists())


if __name__ == "__main__":
    unittest.main()
