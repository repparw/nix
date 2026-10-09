"""Validated crash ingress and a native wake gate for Hermes research."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time

JOB_NAME = "Fleet crash triage"
MAX_BYTES = 32768
REQUIRED = {
    "schema_version", "event_id", "host", "boot_id", "timestamp_us",
    "pid", "uid", "executable", "signal", "count",
}
OPTIONAL = {"unit", "frame_signature"}


def validate(event):
    if not isinstance(event, dict) or not REQUIRED <= event.keys():
        raise ValueError("missing event fields")
    if event.keys() - REQUIRED - OPTIONAL:
        raise ValueError("unknown event fields")
    if type(event["schema_version"]) is not int or event["schema_version"] != 1:
        raise ValueError("unsupported event schema")
    if not isinstance(event["host"], str) or event["host"] not in {"alpha", "pi", "epsilon"}:
        raise ValueError("unknown host")
    for field, pattern in [
        ("event_id", r"[0-9a-f]{64}"),
        ("boot_id", r"(?:[0-9a-f]{32}|[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})"),
    ]:
        if not isinstance(event[field], str) or not re.fullmatch(pattern, event[field]):
            raise ValueError("invalid event identity")
    for field, low, high in [
        ("timestamp_us", 1, 2**63 - 1), ("pid", 1, 2**31 - 1),
        ("uid", 0, 2**32 - 1), ("signal", 1, 64), ("count", 1, 1000000),
    ]:
        if type(event[field]) is not int or not low <= event[field] <= high:
            raise ValueError("invalid numeric field")
    executable = event["executable"]
    if (not isinstance(executable, str) or not 1 <= len(executable) <= 1024
            or not executable.startswith("/") or any(ord(c) < 32 or ord(c) == 127 for c in executable)
            or any(p in {".", ".."} for p in executable.split("/"))):
        raise ValueError("invalid executable path")
    unit = event.get("unit", "")
    if not isinstance(unit, str) or len(unit) > 255 or (unit and not re.fullmatch(r"[a-zA-Z0-9@._:\\-]+", unit)):
        raise ValueError("invalid unit")
    frames = event.get("frame_signature", "")
    if (not isinstance(frames, str) or len(frames) > 4000
            or any((ord(c) < 32 and c not in "\n\t") or ord(c) == 127 for c in frames)):
        raise ValueError("invalid frame signature")
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
        os.setgroups([])
        os.setgid(owner.st_gid)
        os.setuid(owner.st_uid)
    crash = home / "crash"
    private_dir(crash)
    inbox = crash / "inbox"
    private_dir(inbox)
    receipts = crash / "receipts"
    private_dir(receipts)
    destination = inbox / (event["event_id"] + ".json")
    receipt = receipts / destination.name
    canonical = json.dumps(event, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    fd, temporary = tempfile.mkstemp(prefix=".ingest-", dir=inbox)
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
    # Exact store path retains package/build identity. No timestamp or PID
    # participates, so another occurrence does not become a new incident.
    unit = re.sub(r"-[0-9a-f]{8,}\.scope$", ".scope", event.get("unit", ""))
    fields = [event["host"], event["executable"], unit, event["signal"], event.get("frame_signature", "")]
    return hashlib.sha256(json.dumps(fields, separators=(",", ":")).encode()).hexdigest()


def gate(home, known_waits, job, now=None):
    now = time.time() if now is None else now
    crash = home / "crash"
    private_dir(crash)
    inbox = crash / "inbox"
    private_dir(inbox)
    state_path = crash / "state.json"
    with open(crash / "state.lock", "a") as lock:
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
                    # Research/delivery completion is not verification of repair.
                    incident["status"] = "investigated"
                else:
                    incident["status"] = "pending"
                    failures = incident.get("failures", 0) + 1
                    incident["failures"] = failures
                    incident["retry_after"] = now + min(21600, 900 * 2 ** min(failures - 1, 5))
        processed = []
        rejected = crash / "rejected"
        for path in sorted(inbox.glob("*.json"))[:256]:
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
                incident["count"] += event["count"]
                incident["first_seen_us"] = min(incident["first_seen_us"], event["timestamp_us"])
                incident["last_seen_us"] = max(incident["last_seen_us"], event["timestamp_us"])
            processed.append(path)
        selected = []
        for key, incident in state["incidents"].items():
            if key in known_waits:
                incident["status"] = "upstream_wait"
                incident["upstream"] = known_waits[key]
                continue
            if incident["status"] == "upstream_wait":
                incident["status"] = "pending"
                incident.pop("upstream", None)
            if incident["status"] == "pending" and incident.get("retry_after", 0) <= now:
                selected.append(key)
                if len(selected) == 5:
                    break
        if selected:
            state["dispatch"] = {"fingerprints": selected, "prior_run_at": job.get("last_run_at")}
        atomic_write(state_path, json.dumps(state, sort_keys=True).encode())
        for path in processed:
            path.unlink(missing_ok=True)
        investigations = []
        for key in selected:
            incident = state["incidents"][key]
            event = incident["event"]
            investigations.append({
                "fingerprint": key, "host": event["host"],
                "executable": event["executable"], "signal": event["signal"],
                "unit": event.get("unit", ""), "frame_signature": event.get("frame_signature", ""),
                "first_seen_us": incident["first_seen_us"],
                "last_seen_us": incident["last_seen_us"], "count": incident["count"],
            })
        return {"wakeAgent": bool(selected), "investigate": investigations}


def current_job():
    from cron.jobs import list_jobs
    jobs = [job for job in list_jobs(include_disabled=True) if job.get("name") == JOB_NAME]
    if len(jobs) != 1:
        raise ValueError("crash triage enrollment is missing or ambiguous")
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
