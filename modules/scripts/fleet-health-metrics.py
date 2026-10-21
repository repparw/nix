"""Publish bounded host facts; Grafana owns thresholds and notifications."""

import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".metrics-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(text)
        os.chmod(name, 0o644)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def metric(metric_name, value, **labels):
    suffix = "{" + ",".join(f"{key}={json.dumps(str(value))}" for key, value in sorted(labels.items())) + "}" if labels else ""
    return f"{metric_name}{suffix} {value}\n"


def command(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=30).stdout.strip()


def mounted_filesystems(text):
    mounts = {}
    for line in text.splitlines():
        fields = line.split()
        separator = fields.index("-")
        if fields[separator + 1] != "autofs":
            mount = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), fields[4])
            mounts[mount] = fields[separator + 1]
    return mounts


def btrfs_usage(text):
    unallocated = re.search(r"Device unallocated:\s+(\d+)", text)
    metadata = re.search(r"Metadata[^\n]*Size:\s*(\d+),\s*Used:\s*(\d+)", text)
    if not unallocated or not metadata or int(metadata[1]) == 0:
        raise ValueError("incomplete btrfs allocation statistics")
    return {"metadata_percent": 100 * int(metadata[2]) / int(metadata[1]),
            "unallocated_bytes": int(unallocated[1])}


def disk_metrics(disks, cached, mounts, statvfs=os.statvfs, usage=lambda mount: command("btrfs", "filesystem", "usage", "-b", mount), now=None):
    now = int(time.time()) if now is None else now
    lines = []
    for disk in disks:
        mount = disk["mount"]
        labels = {"mountpoint": mount, "sleeping": str(disk.get("sleeping", False)).lower()}
        present = mount in mounts
        lines += [metric("fleet_disk_mounted", int(present), **labels),
                  metric("fleet_disk_warning_percent", disk["warn"], **labels),
                  metric("fleet_disk_critical_percent", disk["crit"], **labels)]
        if present:
            stats = statvfs(mount)
            if stats.f_blocks == 0:
                raise ValueError(f"zero-sized filesystem: {mount}")
            # Match df: reserved blocks are excluded from usable capacity.
            used = stats.f_blocks - stats.f_bfree
            capacity = used + stats.f_bavail
            if capacity <= 0:
                raise ValueError(f"filesystem has no usable capacity: {mount}")
            cached[mount] = {"percent": math.ceil(100 * used / capacity), "observed": now}
            if mounts[mount] == "btrfs":
                cached[mount].update(btrfs_usage(usage(mount)))
        previous = cached.get(mount)
        if previous is not None:
            lines += [metric("fleet_disk_used_percent", previous["percent"], **labels),
                      metric("fleet_disk_observed_timestamp_seconds", previous["observed"], **labels)]
            if "metadata_percent" in previous:
                lines += [metric("fleet_btrfs_metadata_used_percent", previous["metadata_percent"], **labels),
                          metric("fleet_btrfs_unallocated_bytes", previous["unallocated_bytes"], **labels)]
    return "".join(lines), cached


def reboot_required(booted=Path("/run/booted-system"), staged=Path("/nix/var/nix/profiles/system")):
    paths = ["initrd", "kernel", "kernel-modules"]
    if not all((root / path).exists() for root in (booted, staged) for path in paths):
        raise ValueError("booted or staged kernel links unavailable")
    return int(any((booted / path).resolve() != (staged / path).resolve() for path in paths))


def host_metrics(settings, state, now):
    lines = [metric("fleet_failed_units", len(command("fleet-unit-snapshot").splitlines())),
             metric("fleet_deployment_paused", int(Path("/var/lib/auto-update/PAUSE").exists()))]
    if settings["rebootCheck"]:
        lines.append(metric("fleet_reboot_required", reboot_required()))
    for unit in settings["requiredUnits"]:
        status = subprocess.run(["systemctl", "is-active", "--quiet", unit], timeout=10, check=False).returncode
        if status not in (0, 3, 4):
            raise RuntimeError(f"cannot determine required unit state: {unit}")
        lines.append(metric("fleet_required_unit_active", int(status == 0), name=unit))
    for service in settings["probes"]:
        lines.append(metric("fleet_service_probe_expected", 1, service=service))
    success = Path("/var/lib/fleet-unit-state/.success/restic-backups-offsite.service")
    last_success = int(success.read_text()) if success.exists() else 0
    lines += [metric("fleet_backup_last_success_timestamp_seconds", last_success),
              metric("fleet_backup_monitoring_since_timestamp_seconds", state.setdefault("since", now))]
    if settings["exports"]:
        report_path = Path("/var/lib/backup-exports/offsite.json")
        report = json.loads(report_path.read_text()) if report_path.exists() else {}
        for name in settings["exports"]:
            result = report.get("exports", {}).get(name, {})
            lines.append(metric("fleet_backup_export_complete", int(result.get("status") == "complete"), export=name))
        lines.append(metric("fleet_backup_export_report_timestamp_seconds", report.get("finishedAt", 0)))
    return "".join(lines), state


def main():
    settings = json.loads(Path(sys.argv[1]).read_text())
    disks = "--disks" in sys.argv[2:]
    kind = "disks" if disks else "host"
    state_dir = Path(os.environ.get("STATE_DIRECTORY", "/var/lib/fleet-health-metrics"))
    state_path = state_dir / f"{kind}.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    now = int(time.time())
    if disks:
        lines, state = disk_metrics(settings["disks"], state, mounted_filesystems(Path("/proc/self/mountinfo").read_text()), now=now)
    else:
        lines, state = host_metrics(settings, state, now)
    lines += metric("fleet_health_collection_timestamp_seconds", now, collector=kind)
    atomic_write(state_path, json.dumps(state))
    atomic_write(Path("/var/lib/fleet-metrics/textfile") / f"fleet-{kind}.prom", lines)


if __name__ == "__main__":
    main()
