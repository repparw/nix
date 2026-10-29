import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("collector", sys.argv.pop(1))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class MetricsTests(unittest.TestCase):
    def test_sleeping_mount_is_never_accessed(self):
        disk = {"mount": "/media", "warn": 95, "crit": 98, "sleeping": True}
        mounts = collector.mounted_filesystems("1 0 0:1 / /media rw - autofs systemd-1 rw")
        def forbidden(_path):
            self.fail("an unmounted media path was accessed")
        text, cached = collector.disk_metrics([disk], {}, mounts, forbidden, forbidden, now=10)
        self.assertIn('fleet_disk_mounted{mountpoint="/media",sleeping="true"} 0', text)
        self.assertNotIn("fleet_disk_used_percent", text)
        self.assertEqual(cached, {})

    def test_cached_media_usage_survives_unmount(self):
        disk = {"mount": "/media", "warn": 95, "crit": 98, "sleeping": True}
        text, _ = collector.disk_metrics([disk], {"/media": {"percent": 96, "observed": 10}}, {}, now=20)
        self.assertIn('fleet_disk_used_percent{mountpoint="/media",sleeping="true"} 96', text)
        self.assertIn('fleet_disk_observed_timestamp_seconds{mountpoint="/media",sleeping="true"} 10', text)

    def test_reserved_blocks_match_df_and_thresholds_survive(self):
        stats = SimpleNamespace(f_blocks=1000, f_bfree=300, f_bavail=200)
        text, _ = collector.disk_metrics([{"mount": "/persist", "warn": 70, "crit": 85}], {},
                                        {"/persist": "ext4"}, lambda _: stats, now=10)
        self.assertIn('fleet_disk_used_percent{mountpoint="/persist",sleeping="false"} 78', text)
        self.assertIn('fleet_disk_critical_percent{mountpoint="/persist",sleeping="false"} 85', text)

    def test_btrfs_allocation_is_bytes_not_device_slack(self):
        data = "Device unallocated: 1073741824\nMetadata,DUP: Size:1000, Used:860 (86.00%)"
        self.assertEqual(collector.btrfs_usage(data), {"metadata_percent": 86, "unallocated_bytes": 1073741824})
        with self.assertRaises(ValueError):
            collector.btrfs_usage("metadata unavailable")

    def test_atomic_publish_replaces_complete_file(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "facts.prom"
            collector.atomic_write(path, "previous 1\n")
            collector.atomic_write(path, collector.metric("unit_active", 0, name='unit"\\name'))
            self.assertEqual(list(Path(root).iterdir()), [path])
            self.assertEqual(path.stat().st_mode & 0o777, 0o644)
            self.assertIn('name="unit\\"\\\\name"', path.read_text())

    def test_reboot_compares_kernel_links_not_generation_names(self):
        with tempfile.TemporaryDirectory() as root:
            base = Path(root)
            old, new = base / "old", base / "new"
            old.mkdir(); new.mkdir()
            for name in ["initrd", "kernel", "kernel-modules"]:
                target = base / name
                target.touch()
                (old / name).symlink_to(target)
                (new / name).symlink_to(target)
            self.assertEqual(collector.reboot_required(old, new), 0)
            (new / "kernel").unlink()
            (new / "kernel").touch()
            self.assertEqual(collector.reboot_required(old, new), 1)
            (new / "kernel").unlink()
            with self.assertRaises(ValueError):
                collector.reboot_required(old, new)

    def test_backup_success_is_not_inferred_from_export_preparation(self):
        settings = {"requiredUnits": [], "exports": ["paperless"], "probes": ["paperless"], "rebootCheck": True}
        report = {"finishedAt": 99, "exports": {"paperless": {"status": "complete"}}}
        def exists(path):
            return str(path).endswith("offsite.json")
        with patch.object(collector, "command", return_value="failed.service"), \
             patch.object(collector, "reboot_required", return_value=0), \
             patch.object(Path, "exists", exists), \
             patch.object(Path, "read_text", return_value=json.dumps(report)):
            text, state = collector.host_metrics(settings, {}, 100)
        self.assertIn('fleet_failed_unit{name="failed.service"} 1', text)
        self.assertIn("fleet_backup_last_success_timestamp_seconds 0", text)
        self.assertIn('fleet_backup_export_complete{export="paperless"} 1', text)
        self.assertEqual(state["since"], 100)

    def test_failed_unit_metric_is_per_unit_and_absent_when_healthy(self):
        settings = {"requiredUnits": [], "exports": [], "probes": [], "rebootCheck": False}
        with patch.object(collector, "command", return_value="first.service\nsecond.service"), \
             patch.object(Path, "exists", return_value=False):
            text, _ = collector.host_metrics(settings, {}, 100)
        self.assertIn('fleet_failed_unit{name="first.service"} 1', text)
        self.assertIn('fleet_failed_unit{name="second.service"} 1', text)
        self.assertIn("fleet_failed_units 2", text)

        with patch.object(collector, "command", return_value=""), \
             patch.object(Path, "exists", return_value=False):
            healthy, _ = collector.host_metrics(settings, {}, 101)
        self.assertNotIn("fleet_failed_unit{", healthy)
        self.assertIn("fleet_failed_units 0", healthy)
        self.assertIn("fleet_deployment_paused 0", healthy)


unittest.main()
