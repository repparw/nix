import importlib.util
import json
import subprocess
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("collector", sys.argv.pop(1))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)
rules = {rule["uid"]: rule for rule in json.loads(Path(sys.argv.pop(1)).read_text())}


class MetricsTests(unittest.TestCase):
    def test_cloud_policies_preserve_legacy_thresholds_and_fail_closed(self):
        cases = []
        def scenario(rule, values, expected, labels, evaluation="4m", interval="1m"):
            output_labels = {k: v for k, v in labels.items() if k != "sleeping"}
            label_text = "{" + ",".join(f"{k}={json.dumps(v)}" for k, v in sorted(labels.items())) + "}"
            cases.append({"interval": interval, "input_series": [
                {"series": name + label_text, "values": f"{value}+0x32"} for name, value in values.items()
            ], "promql_expr_test": [{"expr": "(" + rules["fleet_cloud_" + rule]["expr"] + ") > bool 0",
                "eval_time": evaluation, "exp_samples": [{"labels": "{" + ",".join(f"{k}={json.dumps(v)}" for k, v in sorted(output_labels.items())) + "}", "value": expected}]}]})
        disk = {"host": "epsilon", "mountpoint": "/persist", "sleeping": "false"}
        values = {"fleet_disk_used_percent": 80, "fleet_disk_warning_percent": 70, "fleet_disk_critical_percent": 85}
        scenario("disk_warning", values, 1, disk)
        scenario("disk_warning", values, 1, disk | {"sleeping": "true"})
        scenario("disk_critical", values, 0, disk)
        scenario("disk_critical", values | {"fleet_disk_used_percent": 86}, 1, disk)
        allocation = {"fleet_btrfs_metadata_used_percent": 80, "fleet_btrfs_unallocated_bytes": 1073741824}
        scenario("btrfs_critical", allocation, 1, disk)
        scenario("btrfs_warning", allocation | {"fleet_btrfs_metadata_used_percent": 86, "fleet_btrfs_unallocated_bytes": 5368709120}, 1, disk)
        scenario("units", {"fleet_failed_unit": 1}, 1, {"host": "pi", "name": "failed.service"})
        cases.append({
            "interval": "1m",
            "input_series": [
                {"series": 'fleet_health_collection_timestamp_seconds{host="pi",collector="host"}', "values": "100+0x32"},
                {"series": 'fleet_health_collection_timestamp_seconds{host="epsilon",collector="host"}', "values": "100+0x32"},
                {"series": 'fleet_failed_unit{host="pi",name="a.service"}', "values": "1+0x32"},
                {"series": 'fleet_failed_unit{host="pi",name="b.service"}', "values": "1+0x32"},
            ],
            "promql_expr_test": [{
                "expr": "(" + rules["fleet_cloud_units"]["expr"] + ") > bool 0",
                "eval_time": "4m",
                "exp_samples": [
                    {"labels": '{host="pi",name="a.service"}', "value": 1},
                    {"labels": '{host="pi",name="b.service"}', "value": 1},
                    {"labels": '{host="epsilon"}', "value": 0},
                ]
            }]
        })
        scenario("reboot", {"fleet_reboot_required": 1}, 1, {"host": "alpha"})
        scenario("reboot", {"fleet_reboot_required": 0}, 0, {"host": "alpha"})
        scenario("reboot_stuck", {"fleet_reboot_required": 1}, 1, {"host": "pi"}, "27h", "1h")
        scenario("reboot_stuck", {"fleet_reboot_required": 0}, 0, {"host": "epsilon"}, "27h", "1h")
        scenario("required_unit", {"fleet_required_unit_active": 0}, 1, {"host": "pi", "name": "traefik.service"})
        scenario("http", {"fleet_service_probe_expected": 1}, 1, {"host": "pi", "service": "missing"})
        scenario("http", {"fleet_service_probe_expected": 1, "probe_success": 1}, 0, {"host": "pi", "service": "available"})
        backup = {"fleet_backup_last_success_timestamp_seconds": 0, "fleet_backup_monitoring_since_timestamp_seconds": 0}
        scenario("backup_stale", backup, 0, {"host": "pi"}, "1h", "1h")
        scenario("backup_stale", backup, 1, {"host": "pi"}, "31h", "1h")
        with tempfile.TemporaryDirectory() as root:
            tests = Path(root) / "policies.yml"
            tests.write_text(json.dumps({"evaluation_interval": "1m", "tests": cases}))
            result = subprocess.run(["promtool", "test", "rules", str(tests)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            policy = Path(root) / "rules.yml"
            policy.write_text(json.dumps({"groups": [{"name": "fleet-cloud", "rules": [
                {"alert": rule["uid"], "expr": "(" + rule["expr"] + ") > 0", "for": rule["pending"]} for rule in rules.values()
            ]}]}))
            result = subprocess.run(["promtool", "check", "rules", str(policy)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

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

    def test_reboot_metric_follows_predicate_exit_codes(self):
        # The shell predicate owns link comparison (fleet-reboot-required
        # test.py); the collector only maps its exit codes onto the metric.
        def outcome(code, stderr=b""):
            return lambda *_args, **_kwargs: SimpleNamespace(
                returncode=code, stderr=stderr, stdout=b""
            )
        self.assertEqual(collector.reboot_required(run=outcome(0)), 1)
        self.assertEqual(collector.reboot_required(run=outcome(1)), 0)
        with self.assertRaises(ValueError):
            collector.reboot_required(run=outcome(2, b"missing /run/booted-system/kernel"))
        with self.assertRaises(ValueError):
            collector.reboot_required(run=outcome(255, b""))

    def test_backup_success_is_not_inferred_from_export_preparation(self):
        settings = {"requiredUnits": [], "exports": ["paperless"], "probes": ["paperless"]}
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
        settings = {"requiredUnits": [], "exports": [], "probes": []}
        with patch.object(collector, "command", return_value="first.service\nsecond.service"), \
             patch.object(collector, "reboot_required", return_value=0), \
             patch.object(Path, "exists", return_value=False):
            text, _ = collector.host_metrics(settings, {}, 100)
        self.assertIn('fleet_failed_unit{name="first.service"} 1', text)
        self.assertIn('fleet_failed_unit{name="second.service"} 1', text)
        self.assertIn("fleet_failed_units 2", text)

        with patch.object(collector, "command", return_value=""), \
             patch.object(collector, "reboot_required", return_value=0), \
             patch.object(Path, "exists", return_value=False):
            healthy, _ = collector.host_metrics(settings, {}, 101)
        self.assertNotIn("fleet_failed_unit{", healthy)
        self.assertIn("fleet_failed_units 0", healthy)
        self.assertIn("fleet_deployment_paused 0", healthy)


unittest.main()
