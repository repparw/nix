import importlib.util
import json
from pathlib import Path
import stat
import sys
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("backup", sys.argv.pop(1))
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class BackupTests(unittest.TestCase):
    def test_private_complete_export_and_failed_refresh_preserves_previous(self):
        requested = []

        def fetch(endpoint):
            requested.append(endpoint)
            if endpoint == "/api/folders?limit=1000":
                return [{"uid": "folder"}]
            if endpoint.startswith("/api/search?"):
                return [{"uid": "fleet"}] if endpoint.endswith("page=1") else []
            return {"fixture": endpoint}

        with tempfile.TemporaryDirectory() as root:
            destination = Path(root) / "state"
            self.assertEqual(backup.export(fetch, destination), 1)
            archive = destination / "grafana-cloud-state.tar.gz"
            self.assertEqual(stat.S_IMODE(archive.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o700)
            with tarfile.open(archive) as handle:
                manifest = json.load(handle.extractfile("manifest.json"))
                self.assertEqual(manifest["dashboards"], 1)
                self.assertIn("dashboard-fleet-permissions.json", manifest["files"])
                self.assertIn("folder-folder-permissions.json", manifest["files"])
                self.assertIn("decrypt=true", json.load(handle.extractfile("contact-points.json"))["fixture"])
            previous = archive.read_bytes()

            def failing_fetch(endpoint):
                if endpoint == "/api/v1/provisioning/templates":
                    raise RuntimeError("Cloud unavailable")
                return fetch(endpoint)

            with self.assertRaisesRegex(RuntimeError, "Cloud unavailable"):
                backup.export(failing_fetch, destination)
            self.assertEqual(archive.read_bytes(), previous)
            self.assertEqual(list(destination.iterdir()), [archive])
            self.assertIn("/api/search?type=dash-db&limit=1000&page=2", requested)

    def test_redirect_cannot_forward_backup_credentials(self):
        with self.assertRaisesRegex(RuntimeError, "redirect"):
            backup.NoRedirects().redirect_request(None, None, 302, "Found", {}, "https://other.example")


if __name__ == "__main__":
    unittest.main()
