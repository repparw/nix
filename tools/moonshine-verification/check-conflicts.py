#!/usr/bin/env python3
"""Check a host procfs view immediately before a functional GPU smoke run."""

import argparse
from pathlib import Path
import sys


def conflicts(proc):
    # These processes represent a competing stream, game, or GPU test. Browser
    # and desktop compositor GPU use is intentionally permitted.
    exclusive = {"moonshine-bench", "vkcube", "vkmark", "gamescope", "reaper"}
    found = []
    for entry in proc.iterdir():
        if not entry.name.isdecimal():
            continue
        try:
            comm = (entry / "comm").read_text().strip()
            cgroup = (entry / "cgroup").read_text()
            if "moonshine-session.service" in cgroup:
                found.append((entry.name, "Moonshine session"))
            elif comm in exclusive:
                found.append((entry.name, comm))
            elif comm.startswith("python"):
                args = (entry / "cmdline").read_bytes().split(b"\0")
                if any(Path(arg.decode(errors="replace")).name == "verify_video.py" for arg in args):
                    found.append((entry.name, "video verification"))
        except FileNotFoundError:
            # Processes can exit between listing procfs and reading their files.
            continue
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proc", type=Path, default=Path("/run/host-proc"))
    args = parser.parse_args()
    try:
        if not (args.proc / "1" / "cgroup").is_file():
            raise OSError("host procfs is unavailable")
        found = conflicts(args.proc)
    except OSError as exc:
        print(f"Cannot check host conflicts: {exc}", file=sys.stderr)
        return 2
    if found:
        for pid, reason in found:
            print(f"Conflicting host workload: {reason} (pid {pid})", file=sys.stderr)
        return 1
    print("No known conflicting stream, game, or verification workload found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
