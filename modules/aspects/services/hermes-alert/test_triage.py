"""Offline tests for the authenticated Grafana incident intake."""
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
from http.server import HTTPServer
import urllib.error
import urllib.request
import unittest
import sys

spec = importlib.util.spec_from_file_location("triage", sys.argv.pop(1))
triage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(triage)


def webhook(status="firing", severity="critical", service="authelia", host="epsilon"):
    return {
        "status": status,
        "alerts": [{
            "status": status, "fingerprint": "a1b2c3d4e5f67890",
            "startsAt": "2026-11-14T18:00:00Z",
            "labels": {"host": host, "service": service, "severity": severity,
                       "alertname": "ServiceUnavailable"},
            "annotations": {"summary": "Authelia stopped responding"},
            "generatorURL": "https://repparw.grafana.net/alerting/foo",
        }],
    }


class Triage(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.state = Path(temp.name) / "state"
        self.job = {"last_run_at": "before", "last_status": "ok"}
        self.token = Path(temp.name) / "token"
        self.token.write_text("q" * 48)

    def test_only_critical_services_or_explicit_opt_in(self):
        self.assertEqual(len(triage.normalize(webhook(), 10)), 1)
        self.assertEqual(triage.normalize(webhook(severity="warning"), 10), [])
        self.assertEqual(triage.normalize(webhook(host="unknown"), 10), [])
        item = webhook(severity="warning", service="")
        item["alerts"][0]["labels"]["agent_triage"] = "true"
        self.assertEqual(len(triage.normalize(item, 10)), 1)

    def test_dedup_delivery_and_resolution(self):
        payload = webhook()
        self.assertEqual(triage.ingest(self.state, payload, now=100), 1)
        self.assertEqual(triage.ingest(self.state, payload, now=101), 1)
        self.assertEqual(len(list((self.state / "events").glob("*.json"))), 1)
        first = triage.gate(self.state, self.job, now=110)
        self.assertTrue(first["wakeAgent"])
        self.assertEqual(first["investigate"][0]["service"], "authelia")
        self.job["last_run_at"] = "after"
        self.assertFalse(triage.gate(self.state, self.job, now=120)["wakeAgent"])
        triage.ingest(self.state, webhook(status="resolved"), now=130)
        self.assertFalse(triage.gate(self.state, self.job, now=140)["wakeAgent"])
        triage.ingest(self.state, payload, now=150)
        self.assertFalse(triage.gate(self.state, self.job, now=160)["wakeAgent"])

    def test_resolved_before_cron_does_not_trigger_investigation(self):
        triage.ingest(self.state, webhook(), now=100)
        triage.ingest(self.state, webhook(status="resolved"), now=110)
        self.assertFalse(triage.gate(self.state, self.job, now=120)["wakeAgent"])

    def test_retry_on_failed_cron_job(self):
        triage.ingest(self.state, webhook(), now=100)
        self.assertTrue(triage.gate(self.state, self.job, now=120)["wakeAgent"])
        self.job.update(last_run_at="after", last_status="error")
        self.assertFalse(triage.gate(self.state, self.job, now=121)["wakeAgent"])
        self.assertTrue(triage.gate(self.state, self.job, now=1021)["wakeAgent"])

    def test_full_queue_preserves_existing_updates_and_requests_retry(self):
        original_limit = triage.MAX_EVENTS
        triage.MAX_EVENTS = 1
        self.addCleanup(setattr, triage, "MAX_EVENTS", original_limit)
        first = webhook()
        triage.ingest(self.state, first, now=100)
        self.assertEqual(triage.ingest(self.state, first, now=110), 1)
        self.assertEqual(triage.ingest(self.state, webhook(status="resolved"), now=120), 1)
        second = webhook()
        second["alerts"][0]["fingerprint"] = "abcdef9876543210"
        with self.assertRaises(triage.QueueFullError):
            triage.ingest(self.state, second, now=130)
        self.assertEqual(len(list((self.state / "events").glob("*.json"))), 1)

    def test_invalid_and_oversized_alert_group(self):
        with self.assertRaises(ValueError):
            triage.normalize({"alerts": [{}] * 65}, 10)
        with self.assertRaises(ValueError):
            triage.normalize({"bad": "payload"}, 10)
        self.assertEqual(triage.normalize(webhook(service="../etc"), 10), [])

    def test_bearer_auth_and_body_limits(self):
        triage.Handler.state = self.state
        triage.Handler.token_file = self.token
        server = HTTPServer(("127.0.0.1", 0), triage.Handler)
        self.addCleanup(server.server_close)
        runner = threading.Thread(target=server.serve_forever, daemon=True)
        runner.start()
        self.addCleanup(server.shutdown)
        url = f"http://127.0.0.1:{server.server_port}/hooks/grafana"
        payload = json.dumps(webhook()).encode()

        def post(body, authorization=None):
            headers = {"Content-Type": "application/json"}
            if authorization:
                headers["Authorization"] = authorization
            request = urllib.request.Request(url, data=body, headers=headers)
            try:
                with urllib.request.urlopen(request, timeout=2) as response:
                    return response.status
            except urllib.error.HTTPError as error:
                return error.code

        self.assertEqual(post(payload), 401)
        self.assertEqual(post(payload, "Bearer bad"), 401)
        self.assertEqual(post(b"x" * (triage.MAX_BODY + 1), "Bearer " + "q" * 48), 413)
        self.assertEqual(post(b"{", "Bearer " + "q" * 48), 422)
        self.assertEqual(post(payload, "Bearer " + "q" * 48), 202)
        self.assertEqual(len(list((self.state / "events").glob("*.json"))), 1)


if __name__ == "__main__":
    unittest.main()
