"""Exercise native API adapters against HTTP and SQLite export fixtures."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from zipfile import ZipFile


ADAPTER = Path(sys.argv.pop(1))


class NativeBackupTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.calls = []
        self.mode = "valid"
        self.api_key = "test-backup-secret"
        self.kind = "servarr"
        self.version = "v3"
        self.app = "sonarr"
        self.output = self.root / "Backups" / "manual"
        self.output.mkdir(parents=True)
        self.database = self.root / "database.db"
        with sqlite3.connect(self.database) as database:
            database.execute("CREATE TABLE state(value)")
            database.execute("INSERT INTO state VALUES (42)")
        test = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def send_json(self, value, status=200):
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                if value is not None:
                    self.wfile.write(json.dumps(value).encode())

            def do_POST(self):
                test.calls.append(("POST", self.path))
                if self.headers.get("X-Api-Key") != "test-backup-secret":
                    self.send_json({}, 401)
                    return
                if test.kind == "bazarr":
                    if self.path != "/api/system/backups":
                        self.send_json({}, 404)
                        return
                    threading.Timer(0.05, test.publish).start()
                    self.send_json(None, 204)
                else:
                    if self.path != f"/api/{test.version}/command":
                        self.send_json({}, 404)
                        return
                    body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                    if body != {"name": "Backup"}:
                        self.send_json({}, 400)
                        return
                    self.send_json({"id": 7, "status": "queued"})

            def do_GET(self):
                test.calls.append(("GET", self.path))
                if self.path != f"/api/{test.version}/command/7":
                    self.send_json({}, 404)
                    return
                if test.mode == "failed-command":
                    self.send_json({"status": "failed"})
                    return
                if test.mode != "stale":
                    test.publish()
                self.send_json({"status": "completed"})

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temporary.cleanup()

    def publish(self):
        path = self.output / f"{self.app}_backup_test.zip"
        with ZipFile(path, "w") as archive:
            archive.writestr("config.yaml" if self.kind == "bazarr" else "config.xml", "fixture")
            if self.mode != "config-only":
                name = "bazarr.db" if self.kind == "bazarr" else "application.db"
                if self.mode == "corrupt-database":
                    archive.writestr(name, "invalid database")
                else:
                    archive.write(self.database, name)

    def run_adapter(self):
        settings = self.root / "settings"
        if self.kind == "bazarr":
            settings.write_text(json.dumps({"auth": {"apikey": self.api_key}}))
        else:
            settings.write_text(f"<Config><ApiKey>{self.api_key}</ApiKey></Config>")
        config = self.root / "adapter.json"
        config.write_text(json.dumps({
            "app": self.app, "kind": self.kind, "apiVersion": self.version,
            "configFile": str(settings), "backupDir": str(self.output),
            "managedDir": str(self.output.parent / "fleet"),
            "pattern": f"{self.app}_backup_*.zip", "timeoutSeconds": 1,
            "url": f"http://127.0.0.1:{self.server.server_port}",
        }))
        result = subprocess.run([sys.executable, str(ADAPTER), str(config)],
                                text=True, capture_output=True, timeout=5)
        self.assertNotIn("test-backup-secret", result.stdout + result.stderr)
        return result

    def test_sonarr_and_radarr_command_v3(self):
        for app in ["sonarr", "radarr"]:
            self.app = app
            result = self.run_adapter()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(("POST", "/api/v3/command"), self.calls)
            self.assertIn(("GET", "/api/v3/command/7"), self.calls)
            self.assertIn(f"Native {app} backup verified", result.stdout)

    def test_prowlarr_command_v1(self):
        self.app = "prowlarr"
        self.version = "v1"
        result = self.run_adapter()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls, [("POST", "/api/v1/command"), ("GET", "/api/v1/command/7")])

    def test_bazarr_queues_then_produces_native_export(self):
        self.app = "bazarr"
        self.kind = "bazarr"
        result = self.run_adapter()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls, [("POST", "/api/system/backups")])
        self.assertIn("Native bazarr backup verified", result.stdout)

    def test_malformed_key_is_rejected_without_logging_it(self):
        self.api_key = "test-backup-secret\ninvalid"
        result = self.run_adapter()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("API key is missing or malformed", result.stderr)
        self.assertEqual(self.calls, [])

    def test_failed_native_command(self):
        self.mode = "failed-command"
        result = self.run_adapter()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not complete successfully", result.stderr)

    def test_noop_cannot_reuse_an_existing_valid_zip(self):
        self.publish()
        self.mode = "stale"
        result = self.run_adapter()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no fresh valid archive", result.stderr)

    def test_bazarr_config_only_zip_is_not_a_database_backup(self):
        self.app = "bazarr"
        self.kind = "bazarr"
        self.mode = "config-only"
        result = self.run_adapter()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing configuration or a database", result.stderr)

    def test_corrupt_database_in_valid_zip(self):
        self.mode = "corrupt-database"
        result = self.run_adapter()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a database", result.stderr)

    def test_retention_only_removes_old_adapter_archives_after_success(self):
        managed = self.output.parent / "fleet"
        managed.mkdir()
        old = managed / "sonarr_backup_fleet_old.zip"
        old.write_bytes(b"old adapter backup")
        recent = managed / "sonarr_backup_fleet_recent.zip"
        recent.write_bytes(b"recent adapter backup")
        manual = self.output / "sonarr_backup_user.zip"
        manual.write_bytes(b"user manual backup")
        for path in [old, manual]:
            os.utime(path, (time.time() - 29 * 86400,) * 2)
        self.mode = "failed-command"
        self.assertNotEqual(self.run_adapter().returncode, 0)
        self.assertTrue(old.exists())
        self.mode = "valid"
        result = self.run_adapter()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(old.exists())
        self.assertEqual(recent.read_bytes(), b"recent adapter backup")
        self.assertEqual(manual.read_bytes(), b"user manual backup")
        self.assertEqual(len(list(managed.glob("sonarr_backup_fleet_*.zip"))), 2)
        self.assertFalse((self.output / "sonarr_backup_test.zip").exists())


if __name__ == "__main__":
    unittest.main()
