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
        self.persistent = self.root / "persistent"
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

    def run_export(self, stage=None, previous=None, persistent=None, critical=None,
                   expect_ok=True):
        stage = stage or self.stage
        args = [
            sys.executable, str(HANDLER), str(self.home), str(stage),
            str(previous if previous is not None else self.previous),
            json.dumps(self.selected),
            json.dumps(self.excludes),
        ]
        if persistent is not None:
            args += ["--persistent-dir", str(persistent)]
        if critical is not None:
            args += ["--critical", json.dumps(critical)]
        run = subprocess.run(args, capture_output=True, text=True, timeout=60)
        if expect_ok:
            self.assertEqual(run.returncode, 0, run.stderr)
            return json.loads((stage / ".export-status.json").read_text())
        self.assertNotEqual(run.returncode, 0, run.stdout + run.stderr)
        return run

    def listed(self, stage=None):
        stage = stage or self.stage
        raw = (stage / ".home-files").read_bytes()
        return {part for part in raw.split(b"\0") if part}

    def excluded_lines(self, stage=None):
        stage = stage or self.stage
        return set((stage / ".home-excludes").read_text().splitlines())

    def test_ordinary_roots_direct_sqlite_snapshot_and_excludes(self):
        bookmarks = self.write(".config/net.imput.helium/Default/Bookmarks", '{"roots":{}}')
        tofu = self.write("Projects/nix/infra/terraform.tfstate", '{"serial":1}')
        auth = self.write(".local/share/opencode/auth.json", '{"token":"test"}')
        special = self.write(".local/share/opencode/[test]*.txt", "special")
        excluded = self.write(".local/share/opencode/log/current.log", "log")
        self.write(".config/net.imput.helium/Default/DIPS", "excluded")
        db_path = ".local/share/opencode/opencode.db"
        self.database(db_path, "committed WAL row")
        glob_db = ".local/share/opencode/[glob]*.db"
        self.database(glob_db, "glob row")

        report = self.run_export()
        self.assertEqual(report["status"], "complete")
        listed = self.listed()
        # Curated roots are listed (directories as directories, files as files)
        # so live directory churn cannot cause Restic exit code 3.
        for path in (bookmarks, tofu, self.home / ".local/share/opencode"):
            self.assertIn(os.fsencode(path), listed)
        for path in (auth, special, excluded, self.home / db_path,
                     self.home / (db_path + "-wal"),
                     self.home / ".config/net.imput.helium/Default/DIPS"):
            self.assertNotIn(os.fsencode(path), listed)
        for path in (bookmarks, tofu, auth, special):
            self.assertFalse((self.stage / path.relative_to(self.home)).exists())

        excl = self.excluded_lines()
        self.assertIn(str(self.home / ".local/share/opencode/log"), excl)
        self.assertIn(str(self.home / db_path), excl)
        self.assertIn(str(self.home / (db_path + "-wal")), excl)
        self.assertIn(str(self.home / (db_path + "-shm")), excl)
        self.assertIn(str(self.home / (db_path + "-journal")), excl)
        self.assertIn(str(self.home / ".local/share/opencode/\\[glob\\]\\*.db"), excl)

        snapshot = self.stage / db_path
        with sqlite3.connect(snapshot) as db:
            self.assertEqual(db.execute("SELECT value FROM session").fetchall(),
                             [("committed WAL row",)])
            self.assertEqual(db.execute("PRAGMA quick_check").fetchone(), ("ok",))
        self.assertFalse(Path(str(snapshot) + "-wal").exists())
        self.assertTrue((self.stage / ".export-complete").exists())

    def test_locked_db_fallback_hardlinks_and_captures_stderr(self):
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
            self.assertIn("locked", report["databases"][db_path]["error"].lower())
            self.assertFalse((self.stage / ".export-complete").exists())
            # Preserved fallback must hardlink on same filesystem (zero extra tmpfs).
            self.assertEqual(old.stat().st_ino, (self.stage / db_path).stat().st_ino)
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
        self.assertIn(str(wal), self.excluded_lines())
        self.assertFalse((self.stage / rel).exists())

    def test_corrupt_sqlite_extensions_are_not_backed_up_raw(self):
        broken = [self.write(f".local/share/opencode/broken{suffix}", "bad header")
                  for suffix in (".db", ".sqlite", ".sqlite3")]
        report = self.run_export()
        self.assertEqual(report["status"], "degraded")
        self.assertEqual(len(report["failures"]), len(broken))
        excl = self.excluded_lines()
        for path in broken:
            self.assertEqual(report["databases"][str(path.relative_to(self.home))]["status"],
                             "missing")
            self.assertIn(str(path), excl)
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
        self.assertIn(str(bad), self.excluded_lines())
        with sqlite3.connect(self.stage / rel) as db:
            self.assertEqual(db.execute("SELECT value FROM session").fetchone(), ("prior",))

    def test_persistent_known_survives_reboot_empty_tmpfs(self):
        rel = ".local/share/opencode/session-store"
        explicit = ".config/codex/goals_1.sqlite"
        self.selected.append(explicit)
        self.database(rel, "v1")
        self.database(explicit, "g1")
        first = self.run_export(persistent=self.persistent)
        self.assertEqual(first["status"], "complete")

        # Simulate reboot: tmpfs previous does not exist, extensionless DB is corrupt,
        # and explicitly selected SQLite DB was deleted.
        for writer in self.writers:
            writer.close()
        self.writers.clear()
        self.write(rel, "corrupt after reboot")
        (self.home / explicit).unlink()
        after_reboot = self.root / "after-reboot"
        after_reboot.mkdir()
        report = self.run_export(
            stage=after_reboot,
            previous=self.root / "empty-tmpfs",
            persistent=self.persistent,
        )
        self.assertEqual(report["status"], "degraded")
        self.assertEqual(report["databases"][rel]["status"], "missing")
        self.assertEqual(report["databases"][explicit]["status"], "missing")
        self.assertIn(str(self.home / rel), self.excluded_lines(after_reboot))

    def test_slashless_directory_retains_known_database(self):
        self.selected.append(".local/state/nvim/shada")
        rel = ".local/state/nvim/shada/state-store"
        self.database(rel, "v1")
        first = self.run_export(persistent=self.persistent)
        self.assertEqual(first["status"], "complete")
        for writer in self.writers:
            writer.close()
        self.writers.clear()
        self.write(rel, "corrupt header")
        next_stage = self.root / "next-slashless"
        next_stage.mkdir()
        report = self.run_export(stage=next_stage, previous=self.stage,
                                 persistent=self.persistent)
        self.assertEqual(report["status"], "degraded")
        self.assertEqual(report["databases"][rel]["status"], "stale")

    def test_symlinked_parent_dir_does_not_crash_discovery(self):
        target = self.root / "external-dir"
        target.mkdir()
        (target / "note.txt").write_text("hello")
        (self.home / ".config").mkdir(parents=True, exist_ok=True)
        (self.home / ".config/linked-app").symlink_to(target)
        self.selected.append(".config/linked-app/note.txt")
        report = self.run_export()
        self.assertEqual(report["status"], "complete")
        self.assertIn(os.fsencode(self.home / ".config/linked-app/note.txt"), self.listed())

    def test_critical_state_validation_without_staging(self):
        crit = ["Projects/nix/infra/terraform.tfstate"]
        state = self.write(crit[0], '{"version": 4, "serial": 1, "resources": []}')
        report = self.run_export(persistent=self.persistent, critical=crit)
        self.assertEqual(report["status"], "complete")
        self.assertFalse((self.stage / crit[0]).exists())
        self.assertIn(os.fsencode(state), self.listed())

        # Locked state must fail
        lock = state.parent / ".terraform.tfstate.lock.info"
        lock.write_text("{}")
        self.run_export(persistent=self.persistent, critical=crit, expect_ok=False)
        lock.unlink()

        # Corrupt JSON must fail
        state.write_text("not json {{")
        self.run_export(persistent=self.persistent, critical=crit, expect_ok=False)

        # Missing after seen must fail
        state.unlink()
        self.run_export(persistent=self.persistent, critical=crit, expect_ok=False)

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
