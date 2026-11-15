"""Authenticated Grafana alert intake and Hermes wake gate. No host actions."""
import argparse
import fcntl
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time

JOB = "Fleet alert triage"
HOSTS = {"alpha", "epsilon", "pi"}
MAX_BODY = 65536
MAX_EVENTS = 1024


class QueueFullError(Exception):
    """Transient backpressure: Grafana should retry instead of dropping events."""


def compact(value, limit):
    if not isinstance(value, str):
        return ""
    return "".join(c for c in value[:limit] if ord(c) >= 32 or c == "\n")


def normalize(payload, now=None):
    now = int(time.time() if now is None else now)
    if not isinstance(payload, dict) or not isinstance(payload.get("alerts"), list):
        raise ValueError("invalid Grafana payload")
    if len(payload["alerts"]) > 64:
        raise ValueError("too many alerts")
    events = []
    for item in payload["alerts"]:
        if not isinstance(item, dict) or not isinstance(item.get("labels"), dict):
            continue
        labels = item["labels"]
        host, service = labels.get("host"), compact(labels.get("service"), 80)
        opted_in = labels.get("agent_triage") in ("true", "1")
        critical = labels.get("severity") == "critical" and service
        if host not in HOSTS or not (opted_in or critical):
            continue
        if service and not re.fullmatch(r"[\w.-]{1,80}", service, re.ASCII):
            continue
        fingerprint, starts = item.get("fingerprint"), item.get("startsAt")
        if (not isinstance(fingerprint, str) or
                not re.fullmatch(r"[a-fA-F0-9]{8,64}", fingerprint) or
                not isinstance(starts, str) or not 10 <= len(starts) <= 64):
            continue
        status = item.get("status", payload.get("status"))
        if status not in ("firing", "resolved"):
            continue
        alertname = compact(labels.get("alertname"), 100)
        if not alertname:
            continue
        annotations = item.get("annotations") if isinstance(item.get("annotations"), dict) else {}
        url = item.get("generatorURL", "")
        if not isinstance(url, str) or not url.startswith("https://repparw.grafana.net/"):
            url = ""
        identity = hashlib.sha256((fingerprint.lower() + "\0" + starts).encode()).hexdigest()
        events.append({
            "id": identity, "status": status, "host": host, "service": service,
            "alertname": alertname, "starts_at": starts, "received_at": now,
            "severity": compact(labels.get("severity"), 20),
            "summary": compact(annotations.get("summary"), 400),
            "description": compact(annotations.get("description"), 800),
            "grafana_url": url[:512],
        })
    return events


def private_dir(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.is_symlink() or not path.is_dir():
        raise ValueError("unsafe state directory")
    os.chmod(path, 0o700)


def atomic_write(path, payload):
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".staged-")
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(json.dumps(payload, sort_keys=True).encode())
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp, path)
        directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def ingest(state, payload, now=None):
    events = normalize(payload, now)
    if not events:
        return 0
    inbox = state / "events"
    private_dir(inbox)
    existing = {path.stem for path in inbox.glob("*.json")}
    incoming = {event["id"] for event in events}
    if len(existing | incoming) > MAX_EVENTS:
        raise QueueFullError("event queue full")
    for event in events:
        path = inbox / (event["id"] + ".json")
        if path.is_symlink():
            raise ValueError("unsafe event path")
        previous = json.loads(path.read_text()) if path.exists() else {}
        if previous.get("status") == "resolved" and event["status"] == "firing":
            continue
        if previous.get("status") != event["status"]:
            atomic_write(path, event)
    return len(events)


def gate(state, job, now=None):
    now = int(time.time() if now is None else now)
    private_dir(state)
    with (state / "gate.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        db = state / "state.json"
        data = json.loads(db.read_text()) if db.exists() else {"incidents": {}}
        incidents = data["incidents"]
        for path in sorted((state / "events").glob("*.json")) if (state / "events").exists() else []:
            if path.is_symlink() or not re.fullmatch(r"[a-f0-9]{64}\.json", path.name):
                continue
            try:
                event = json.loads(path.read_text())
                if path.name != event["id"] + ".json":
                    continue
                old = incidents.get(event["id"])
                if old is None:
                    incidents[event["id"]] = {
                        "event": event, "status": "pending" if event["status"] == "firing" else "resolved",
                        "retry_after": 0,
                    }
                elif event["status"] == "resolved":
                    old["status"] = "resolved"
                if (now - event["received_at"] > 30 * 86400 and
                        incidents[event["id"]]["status"] in ("reported", "resolved")):
                    del incidents[event["id"]]
                    path.unlink()
            except (ValueError, KeyError, TypeError, OSError):
                continue
        pending = data.pop("dispatch", None)
        if pending:
            completed = job.get("last_run_at") != pending["prior_run_at"]
            success = completed and job.get("last_status") == "ok" and not (
                job.get("last_error") or job.get("last_delivery_error"))
            for identity in pending["ids"]:
                entry = incidents.get(identity)
                if entry and entry["status"] == "dispatched":
                    entry["status"] = "reported" if success else "pending"
                    if not success:
                        entry["retry_after"] = now + 900
        selected = [identity for identity, entry in sorted(incidents.items())
                    if entry["status"] == "pending" and entry["retry_after"] <= now][:5]
        for identity in selected:
            incidents[identity]["status"] = "dispatched"
        if selected:
            data["dispatch"] = {"ids": selected, "prior_run_at": job.get("last_run_at")}
        atomic_write(db, data)
        return {"wakeAgent": bool(selected),
                "investigate": [incidents[identity]["event"] for identity in selected]}


class Handler(BaseHTTPRequestHandler):
    state = None
    token_file = None

    def setup(self):
        self.request.settimeout(10)
        super().setup()

    def reply(self, code):
        self.send_response(code)
        self.send_header("Content-Length", "0")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def do_POST(self):
        if self.path != "/hooks/grafana":
            return self.reply(404)
        try:
            token = self.token_file.read_text().strip()
        except OSError:
            return self.reply(503)
        if len(token) < 32 or not hmac.compare_digest(
            self.headers.get("Authorization", ""), "Bearer " + token
        ):
            return self.reply(401)
        try:
            if self.headers.get("Transfer-Encoding"):
                return self.reply(400)
            length = int(self.headers.get("Content-Length", ""))
            if not 0 < length <= MAX_BODY:
                return self.reply(413)
            payload = json.loads(self.rfile.read(length))
            ingested = ingest(self.state, payload)
        except QueueFullError:
            return self.reply(503)
        except (ValueError, TypeError, KeyError):
            return self.reply(422)
        except OSError:
            return self.reply(503)
        print(f"grafana-alert-triage: accepted {ingested} alerts", flush=True)
        self.reply(202)

    def log_message(self, *_):
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("serve", "gate"))
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--token-file", type=Path)
    parser.add_argument("--port", type=int, default=3988)
    args = parser.parse_args()
    os.umask(0o077)
    if args.mode == "serve":
        if not args.token_file:
            raise ValueError("token file required")
        private_dir(args.state)
        Handler.state = args.state
        Handler.token_file = args.token_file
        HTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
    else:
        from cron.jobs import list_jobs
        jobs = [item for item in list_jobs(include_disabled=True)
                if item.get("name") == JOB]
        if len(jobs) != 1:
            raise ValueError("Fleet alert triage cron not enrolled")
        print(json.dumps(gate(args.state, jobs[0]), sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        print(f"grafana-alert-triage: {type(error).__name__}", file=sys.stderr)
        sys.exit(1)
