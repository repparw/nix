"""Parse a stripped nix store diff-closures report into a package-update event.

Emits one protocol-v1 JSON event on standard output containing only the
targeted version metadata Hermes triages: relevant packages with a real
version transition. Size-only rebuilds, path additions and removals without
version metadata, and unknown packages are omitted - the raw diff stays on
disk for deeper inspection.
"""

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path
import re
import sys
import time

TRANSITION = "⟶"  # U+27F6, as emitted by nix store diff-closures
EMPTY = "∅"  # U+2205: path absent on one side
MISSING = "ε"  # U+03B5: path present without version metadata

# Relevant packages by closure-name prefix, from the fleet's triage tiers.
RELEVANT = (
    "linux", "mesa", "systemd", "nix",
    "firefox", "chromium", "gamescope", "moonshine", "steam", "niri",
    "neovim", "heroic", "jellyfin", "authelia",
)

HOSTS = ("alpha", "pi", "epsilon")


def relevant(name):
    return any(name == prefix or name.startswith(prefix + "-") for prefix in RELEVANT)


def strip_size(text):
    # Drop the trailing size delta nix appends after a comma.
    return text.rsplit(",", 1)[0].strip() if "," in text else text.strip()


def parse_diff(diff):
    packages = []
    seen = set()
    for line in diff.splitlines():
        line = line.strip()
        if TRANSITION not in line or ":" not in line:
            continue
        head, _, tail = line.partition(": ")
        if TRANSITION not in tail:
            continue
        old, _, new = tail.partition(TRANSITION)
        old = strip_size(old)
        new = strip_size(new)
        # Multiple paths can share one transition; keep the first relevant one.
        for name in (part.strip() for part in head.split(",")):
            if not name or name in seen or not relevant(name):
                continue
            if old == EMPTY or new == EMPTY:
                continue  # path addition or removal, not a version transition
            packages.append({
                "name": name,
                "from": "" if old == MISSING else old,
                "to": "" if new == MISSING else new,
            })
            seen.add(name)
            break
        if len(packages) >= 32:
            break
    return packages


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host", choices=HOSTS)
    parser.add_argument("revision")
    parser.add_argument("diff_file", type=Path)
    parser.add_argument("--outbox-entry", type=Path)
    args = parser.parse_args()
    if args.outbox_entry and args.outbox_entry.exists():
        print(args.outbox_entry.read_text().strip())
        return

    packages = parse_diff(args.diff_file.read_text())
    if not packages:
        print(json.dumps({"skip": "no relevant version transitions"}))
        return
    timestamp_us = int(time.time() * 1_000_000)
    payload = json.dumps(
        {"host": args.host, "revision": args.revision, "packages": packages, "timestamp_us": timestamp_us},
        sort_keys=True, separators=(",", ":"),
    ).encode()
    event_id = hashlib.sha256(
        json.dumps(
            {"host": args.host, "revision": args.revision,
             "packages": sorted((p["name"], p["from"], p["to"]) for p in packages)},
            sort_keys=True, separators=(",", ":"),
        ).encode()
    ).hexdigest()
    event = json.loads(payload)
    event["event_id"] = event_id
    event["schema_version"] = 1
    serialized = json.dumps(event, sort_keys=True)
    if args.outbox_entry:
        os.umask(0o077)
        destination = args.outbox_entry
        destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd, temporary = tempfile.mkstemp(dir=destination.parent, prefix=".enqueue-")
        try:
            with os.fdopen(fd, "w") as stream:
                stream.write(serialized + "\n")
                stream.flush()
                os.fsync(stream.fileno())
            try:
                os.link(temporary, destination)
            except FileExistsError:
                serialized = destination.read_text().strip()
            directory = os.open(destination.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            os.unlink(temporary)
    print(serialized)


if __name__ == "__main__":
    main()
