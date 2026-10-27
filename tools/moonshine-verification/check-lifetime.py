#!/usr/bin/env python3
"""Refuse a job unless both service lifetimes cover its full budget."""

import argparse
from pathlib import Path
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container-start-file", type=Path, required=True)
    parser.add_argument("--runner-start-us", required=True)
    parser.add_argument("--now", type=float, default=None, help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        now = time.monotonic() if args.now is None else args.now
        container_start = float(args.container_start_file.read_text().strip())
        runner_start = int(args.runner_start_us) / 1_000_000
        if not (0 < container_start <= now and 0 < runner_start <= now):
            raise ValueError("invalid or future service start time")
        container_left = 1800 - (now - container_start)
        runner_left = 1500 - (now - runner_start)
        if min(container_left, runner_left) < 1260:
            print(f"Insufficient service lifetime: container={container_left:.0f}s runner={runner_left:.0f}s; need 1260s", file=sys.stderr)
            return 1
    except (OSError, ValueError, OverflowError) as exc:
        print(f"Cannot verify service lifetime: {exc}", file=sys.stderr)
        return 2
    print(f"Service lifetime remaining: container={container_left:.0f}s runner={runner_left:.0f}s; need 1260s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
