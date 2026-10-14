"""Validated package-update ingress and a weekly wake gate for Hermes research.

Mirrors the Hermes crash intake: the host command `hermes-package-ingest`
accepts one protocol-v1 JSON event on standard input, validates it, drops
privileges to the Hermes home owner, and durably stores receipts and inbox
entries before acknowledging. Receipts reject a reused event ID with different
content, including after the inbox has been consumed.

The gate groups package-version changes by host and upgrade set, deduplicates
previously reported upgrades, and wakes the research agent only when a
pending, previously unreported set is due. Provider or delivery failures stay
pending and retry with a bounded backoff.
"""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sys
import tempfile
import time

JOB_NAME = "Fleet package triage"
MAX_BYTES = 32768
MAX_PACKAGES = 32
REQUIRED = {"schema_version", "event_id", "host", "timestamp_us", "revision", "packages"}
HOSTS = {"alpha", "pi", "epsilon"}


def validate(event):
    if not isinstance(event, dict) or not REQUIRED <= event.keys():
        raise ValueError("missing event fields")
    if event.keys() - REQUIRED:
        raise ValueError("unknown event fields")
    if type(event["schema_version"]) is not int or event["schema_version"] != 1:
        raise ValueError("unsupported event schema")
    if not isinstance(event["host"], str) or event["host"] not in HOSTS:
        raise ValueError("unknown host")
    if not isinstance(event["event_id"], str) or not re.fullmatch(r"[0-9a-f]{64}", event["event_id"]):
        raise ValueError("invalid event identity")
    if type(event["timestamp_us"]) is not int or not 1 <= event["timestamp_us"] <= 2**63 - 1:
        raise ValueError("invalid timestamp")
    revision = event["revision"]
    if (not isinstance(revision, str) or not 1 <= len(revision) <= 128
            or not re.fullmatch(r"[0-9a-zA-Z][0-9a-zA-Z._-]*", revision)):
        raise ValueError("invalid configuration revision")
    packages = event["packages"]
    if not isinstance(packages, list) or not 1 <= len(packages) <= MAX_PACKAGES:
        raise ValueError("invalid package list")
    seen = set()
    for package in packages:
        if not isinstance(package, dict) or package.keys() != {"name", "from", "to"}:
            raise ValueError("invalid package entry")
        for key in ("name", "from", "to"):
            value = package[key]
            if (not isinstance(value, str) or not 0 <= len(value) <= 128
                    or value != value.strip()
                    or any(ord(c) < 32 or ord(c) == 127 for c in value)):
                raise ValueError("invalid package field")
        if not package["name"] or package["name"] in seen:
            raise ValueError("invalid or duplicate package name")
        seen.add(package["name"])
    return event


def decode(raw):
    if len(raw) > MAX_BYTES:
        raise ValueError("event exceeds size limit")

    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("duplicate event fields")
            result[key] = value
        return result

    return validate(json.loads(raw, object_pairs_hook=pairs))


def private_dir(path):
    path.mkdir(mode=0o700, exist_ok=True)
    if path.is_symlink() or not path.is_dir():
        raise ValueError("invalid private directory")
    os.chmod(path, 0o700)
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def atomic_write(path, data):
    fd, temporary = tempfile.mkstemp(prefix=".write-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def ingest(home, raw):
    event = decode(raw)
    if home.is_symlink() or not home.is_dir():
        raise ValueError("Hermes home is unavailable")
    # The host command runs as root, but all queue writes use the shifted
    # Hermes owner. A writable inbox must not become a root file-write API.
    owner = home.stat()
    if os.geteuid() == 0:
        if owner.st_uid == 0:
            raise ValueError("Hermes home must have an unprivileged owner")
        # Enter before dropping privileges: private ancestors may be inaccessible.
        os.chdir(home)
        home = Path(".")
        os.setgroups([])
        os.setgid(owner.st_gid)
        os.setuid(owner.st_uid)
    updates = home / "package-updates"
    private_dir(updates)
    inbox = updates / "inbox"
    private_dir(inbox)
    receipts = updates / "receipts"
    private_dir(receipts)
    destination = inbox / (event["event_id"] + ".json")
    receipt = receipts / destination.name
    canonical = json.dumps(event, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    # mkstemp expands dir to an absolute path, losing the entered-directory
    # access across private ancestors after the UID change.
    temporary = inbox / (".ingest-" + secrets.token_hex(16))
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(canonical)
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temporary, receipt)
        except FileExistsError:
            if receipt.is_symlink() or receipt.read_bytes() != canonical:
                raise ValueError("event identity collision")
        try:
            os.link(receipt, destination)
        except FileExistsError:
            if destination.is_symlink() or destination.read_bytes() != canonical:
                raise ValueError("event identity collision")
        receipts_fd = os.open(receipts, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(receipts_fd)
        finally:
            os.close(receipts_fd)
        directory = os.open(inbox, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        os.unlink(temporary)
    return {"event_id": event["event_id"]}


def fingerprint(event):
    # Host plus the sorted upgrade set: the same upgrade set observed again,
    # under any deployment revision, deduplicates into one incident. The
    # revision stays event metadata, not identity.
    packages = sorted((p["name"], p["from"], p["to"]) for p in event["packages"])
    fields = [event["host"], packages]
    return hashlib.sha256(json.dumps(fields, separators=(",", ":")).encode()).hexdigest()


def gate(home, known_waits, job, now=None):
    now = time.time() if now is None else now
    updates = home / "package-updates"
    private_dir(updates)
    inbox = updates / "inbox"
    private_dir(inbox)
    state_path = updates / "state.json"
    with open(updates / "state.lock", "a") as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = json.loads(state_path.read_text()) if state_path.exists() else {"seen": {}, "incidents": {}}
        dispatch = state.pop("dispatch", None)
        if dispatch:
            completed = job.get("last_run_at") != dispatch.get("prior_run_at")
            failed = bool(job.get("last_error") or job.get("last_delivery_error"))
            for key in dispatch["fingerprints"]:
                incident = state["incidents"][key]
                if completed and job.get("last_status") == "ok" and not failed:
                    # Research/delivery completion is not verification that the
                    # upgrade was acted on; it only means it was reported once.
                    incident["status"] = "reported"
                else:
                    incident["status"] = "pending"
                    failures = incident.get("failures", 0) + 1
                    incident["failures"] = failures
                    incident["retry_after"] = now + min(21600, 900 * 2 ** min(failures - 1, 5))
        processed = []
        rejected = updates / "rejected"
        for path in sorted(inbox.glob("*.json"))[:64]:
            try:
                if path.is_symlink():
                    raise ValueError("symlink event")
                with path.open("rb") as stream:
                    event = decode(stream.read(MAX_BYTES + 1))
                if path.name != event["event_id"] + ".json":
                    raise ValueError("event filename mismatch")
            except (ValueError, UnicodeError, OSError):
                private_dir(rejected)
                os.replace(path, rejected / path.name)
                continue
            event_id = event["event_id"]
            if event_id not in state["seen"]:
                key = fingerprint(event)
                state["seen"][event_id] = key
                incident = state["incidents"].setdefault(key, {
                    "event": event, "first_seen_us": event["timestamp_us"],
                    "last_seen_us": event["timestamp_us"], "count": 0,
                    "status": "pending",
                })
                incident["count"] += 1
                incident["first_seen_us"] = min(incident["first_seen_us"], event["timestamp_us"])
                incident["last_seen_us"] = max(incident["last_seen_us"], event["timestamp_us"])
            processed.append(path)
        selected = []
        for key, incident in state["incidents"].items():
            if key in known_waits:
                incident["status"] = "suppressed"
                incident["suppressed"] = known_waits[key]
                continue
            if incident["status"] == "suppressed":
                incident["status"] = "pending"
                incident.pop("suppressed", None)
            if incident["status"] == "pending" and incident.get("retry_after", 0) <= now:
                selected.append(key)
                if len(selected) == 5:
                    break
        if selected:
            state["dispatch"] = {"fingerprints": selected, "prior_run_at": job.get("last_run_at")}
        atomic_write(state_path, json.dumps(state, sort_keys=True).encode())
        for path in processed:
            path.unlink(missing_ok=True)
        upgrades = []
        for key in selected:
            incident = state["incidents"][key]
            event = incident["event"]
            upgrades.append({
                "fingerprint": key, "host": event["host"], "revision": event["revision"],
                "packages": event["packages"],
                "first_seen_us": incident["first_seen_us"],
                "last_seen_us": incident["last_seen_us"], "count": incident["count"],
            })
        return {"wakeAgent": bool(selected), "investigate": upgrades}


def current_job():
    from cron.jobs import list_jobs
    jobs = [job for job in list_jobs(include_disabled=True) if job.get("name") == JOB_NAME]
    if len(jobs) != 1:
        raise ValueError("package triage enrollment is missing or ambiguous")
    return jobs[0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["ingest", "gate"])
    parser.add_argument("--home", type=Path)
    parser.add_argument("--known-waits", type=Path)
    args = parser.parse_args()
    home = args.home or Path(os.environ.get("HERMES_HOME", str(Path.home() / ".hermes")))
    os.umask(0o077)
    if args.mode == "ingest":
        result = ingest(home, sys.stdin.buffer.read(MAX_BYTES + 1))
    else:
        known = json.loads(args.known_waits.read_text()) if args.known_waits else {}
        if not isinstance(known, dict) or any(not re.fullmatch(r"[0-9a-f]{64}", key) for key in known):
            raise ValueError("invalid known-wait catalog")
        result = gate(home, known, current_job())
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, UnicodeError) as error:
        # Metadata can be attacker-controlled; do not include raw values,
        # tracebacks or arbitrary local filesystem contents in cron context.
        print(json.dumps({"error": type(error).__name__}), file=sys.stderr)
        raise SystemExit(1)
