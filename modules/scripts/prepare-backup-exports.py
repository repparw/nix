"""Prepare exports and check native scheduled artifacts before offsite Restic."""

import fnmatch
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import time


def artifacts(spec):
    cutoff = time.time_ns() - spec["maxAgeSeconds"] * 1_000_000_000
    found = set()

    def scan(directory):
        with os.scandir(directory) as entries:
            for entry in entries:
                if entry.is_dir(follow_symlinks=False):
                    scan(entry.path)
                    continue
                if not fnmatch.fnmatchcase(entry.name, spec["pattern"]):
                    continue
                metadata = entry.stat(follow_symlinks=False)
                if not stat.S_ISREG(metadata.st_mode) or not metadata.st_size:
                    continue
                if metadata.st_mtime_ns < cutoff:
                    continue
                found.add((os.path.relpath(entry.path, spec["path"]), metadata.st_ino,
                           metadata.st_mtime_ns, metadata.st_ctime_ns, metadata.st_size))

    try:
        scan(spec["path"])
    except FileNotFoundError:
        return set()
    return found


def prepare(exports, report_path):
    report = {"startedAt": int(time.time()), "exports": {}, "status": "complete"}
    for name, spec in exports.items():
        try:
            if spec["unit"] is None:
                refreshed = artifacts(spec)
                if not refreshed:
                    raise RuntimeError("no nonempty scheduled artifact within maxAgeSeconds")
            else:
                before = artifacts(spec)
                command = ["systemctl", "--wait"]
                if spec["machine"] is not None:
                    command += ["--machine", spec["machine"]]
                command += ["start", spec["unit"]]
                print(f"Preparing backup export: {name}", flush=True)
                subprocess.run(command, check=True)
                refreshed = artifacts(spec).difference(before)
                if not refreshed:
                    raise RuntimeError("exporter produced no new or refreshed nonempty artifact within maxAgeSeconds")
            report["exports"][name] = {"status": "complete", "artifacts": sorted(item[0] for item in refreshed)}
            print(f"Verified fresh backup export: {name}", flush=True)
        except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
            report["status"] = "incomplete"
            report["exports"][name] = {"status": "failed", "error": str(error)}
            print(f"Backup export failed: {name}: {error}", file=sys.stderr, flush=True)
    report["finishedAt"] = int(time.time())
    report_path.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    if sys.argv[1] == "--check":
        report = json.loads(Path(sys.argv[2]).read_text())
        if report["status"] != "complete":
            failed = ", ".join(name for name, result in report["exports"].items() if result["status"] == "failed")
            sys.exit(f"Offsite snapshot uploaded but incomplete; failed exports: {failed}")
    else:
        prepare(json.loads(Path(sys.argv[1]).read_text()), Path(sys.argv[2]))
