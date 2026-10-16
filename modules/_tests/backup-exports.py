"""Exercise scheduled freshness and synchronous export failure behavior."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("exports", sys.argv.pop(1))
exports = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exports)


class ExportsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "scheduled"
        self.source.mkdir()
        self.spec = {"unit": None, "machine": None, "path": str(self.source),
                     "pattern": "*_backup_*.zip", "maxAgeSeconds": 26 * 3600}
        self.archive = self.source / "app_backup_current.zip"
        self.report = self.root / "report.json"

    def run_exports(self, declarations=None):
        exports.prepare(declarations or {"app": self.spec}, self.report)
        return json.loads(self.report.read_text())

    def test_unchanged_scheduled_archive_accepted_on_repeated_runs_without_command(self):
        self.archive.write_bytes(b"native archive")
        os.utime(self.archive, (time.time() - 25 * 3600,) * 2)
        with patch.object(exports.subprocess, "run") as command:
            for _ in range(2):
                report = self.run_exports()
                self.assertEqual(report["status"], "complete")
                self.assertEqual(report["exports"]["app"]["artifacts"], [self.archive.name])
            command.assert_not_called()

    def test_stale_empty_missing_and_symlink_archives_are_incomplete(self):
        for case in ["stale", "empty", "missing", "symlink"]:
            with self.subTest(case=case):
                self.archive.unlink(missing_ok=True)
                if case == "stale":
                    self.archive.write_bytes(b"old archive")
                    os.utime(self.archive, (time.time() - 27 * 3600,) * 2)
                elif case == "empty":
                    self.archive.touch()
                elif case == "symlink":
                    target = self.root / "outside.zip"
                    target.write_bytes(b"outside")
                    self.archive.symlink_to(target)
                self.assertEqual(self.run_exports()["status"], "incomplete")

    def test_manual_archive_does_not_mask_missing_scheduled_archive(self):
        manual = self.root / "manual"
        manual.mkdir()
        (manual / self.archive.name).write_bytes(b"manual archive")
        self.assertEqual(self.run_exports()["status"], "incomplete")

    def test_producer_must_refresh_even_a_recent_archive(self):
        self.archive.write_bytes(b"existing archive")
        self.spec["unit"] = "app-export.service"
        self.spec["machine"] = "app"
        with patch.object(exports.subprocess, "run") as command:
            self.assertEqual(self.run_exports()["status"], "incomplete")
            command.assert_called_once_with(["systemctl", "--wait", "--machine", "app", "start", "app-export.service"], check=True)

    def test_failed_producer_does_not_block_scheduled_export(self):
        self.archive.write_bytes(b"native archive")
        failed = self.spec | {"unit": "broken.service"}
        with patch.object(exports.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "systemctl")):
            report = self.run_exports({"broken": failed, "scheduled": self.spec})
        self.assertEqual(report["status"], "incomplete")
        self.assertEqual(report["exports"]["scheduled"]["status"], "complete")


unittest.main()
