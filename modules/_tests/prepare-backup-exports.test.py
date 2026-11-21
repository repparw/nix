import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

HANDLER = Path(sys.argv.pop(1))
spec = importlib.util.spec_from_file_location("prepare_backup_exports", HANDLER)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class BackupQuality(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.stage = self.root / "stage"
        self.stage.mkdir()
        self.status = self.stage / ".export-status.json"
        self.export = {
            "unit": None, "machine": None, "path": str(self.stage),
            "pattern": ".export-status.json", "maxAgeSeconds": 3600,
            "statusFile": str(self.status),
        }
        self.report = self.root / "offsite.json"

    def update_status(self, state, *, full_marker=True, pending=False):
        self.status.write_text(json.dumps({
            "schemaVersion": 1, "status": state, "databases": {},
            "recoveryPending": pending, "failures": [{
                "path": ".config/net.imput.helium/Default/DIPS",
                "status": "stale", "verifiedAt": 1700000000,
            }] if state == "degraded" else [],
        }))
        if state == "complete" and full_marker:
            (self.stage / ".export-complete").write_text("verified\\n")

    def test_fresh_degraded_export_does_not_clear_complete_backup_alarm(self):
        self.update_status("degraded")
        mod.prepare({"alpha-home": self.export}, self.report)
        data = json.loads(self.report.read_text())
        self.assertEqual(data["status"], "incomplete")
        self.assertEqual(data["exports"]["alpha-home"]["status"], "degraded")
        self.assertEqual(len(data["exports"]["alpha-home"]["databaseFailures"]), 1)
        with self.assertRaises(SystemExit):
            mod.check(self.report)

    def test_complete_export_allows_success(self):
        self.update_status("complete")
        mod.prepare({"alpha-home": self.export}, self.report)
        self.assertEqual(json.loads(self.report.read_text())["status"], "complete")
        mod.check(self.report)

    def test_complete_requires_full_generation_marker(self):
        self.update_status("complete", full_marker=False)
        mod.prepare({"alpha-home": self.export}, self.report)
        data = json.loads(self.report.read_text())
        self.assertEqual(data["status"], "incomplete")
        self.assertEqual(data["exports"]["alpha-home"]["status"], "failed")

    def test_retry_recovery_is_degraded_until_full_export(self):
        self.update_status("degraded", pending=True)
        report = json.loads(self.status.read_text())
        report["failures"] = []
        self.status.write_text(json.dumps(report))
        mod.prepare({"alpha-home": self.export}, self.report)
        data = json.loads(self.report.read_text())
        self.assertEqual(data["status"], "incomplete")
        self.assertEqual(data["exports"]["alpha-home"]["status"], "degraded")

    def test_missing_or_invalid_quality_is_failure_not_success(self):
        mod.prepare({"alpha-home": self.export}, self.report)
        self.assertEqual(json.loads(self.report.read_text())["status"], "incomplete")
        self.status.write_text("not json")
        mod.prepare({"alpha-home": self.export}, self.report)
        self.assertEqual(json.loads(self.report.read_text())["status"], "incomplete")


if __name__ == "__main__":
    unittest.main()
