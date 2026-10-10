import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("triage", Path(__file__).with_name("triage.py"))
triage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(triage)


def event(identity="a", **changes):
    result = {
        "schema_version": 1, "event_id": identity * 64, "host": "alpha",
        "timestamp_us": 1791540000000000, "revision": "26.11.20261010.4907291",
        "packages": [
            {"name": "mesa", "from": "26.2.2", "to": "26.2.4"},
            {"name": "firefox", "from": "150.0", "to": "151.0"},
        ],
    }
    result.update(changes)
    return result


class ValidationTests(unittest.TestCase):
    def test_valid_event_passes(self):
        self.assertEqual(triage.decode(json.dumps(event()))["host"], "alpha")

    def test_unknown_fields_rejected(self):
        with self.assertRaises(ValueError):
            triage.decode(json.dumps(event(extra="no")))

    def test_missing_fields_rejected(self):
        broken = event()
        del broken["packages"]
        with self.assertRaises(ValueError):
            triage.decode(json.dumps(broken))

    def test_unknown_host_rejected(self):
        with self.assertRaises(ValueError):
            triage.validate(event(host="workstation"))

    def test_bad_event_id_rejected(self):
        with self.assertRaises(ValueError):
            triage.validate(event(event_id="zz" * 64))

    def test_empty_package_list_rejected(self):
        with self.assertRaises(ValueError):
            triage.validate(event(packages=[]))

    def test_too_many_packages_rejected(self):
        many = [{"name": f"p{i}", "from": "1", "to": "2"} for i in range(33)]
        with self.assertRaises(ValueError):
            triage.validate(event(packages=many))

    def test_package_entry_shape_enforced(self):
        with self.assertRaises(ValueError):
            triage.validate(event(packages=[{"name": "mesa", "from": "1", "to": "2", "why": "x"}]))
        with self.assertRaises(ValueError):
            triage.validate(event(packages=[{"name": "", "from": "1", "to": "2"}]))
        with self.assertRaises(ValueError):
            triage.validate(event(packages=[{"name": "mesa", "from": "1", "to": "2"},
                                            {"name": "mesa", "from": "3", "to": "4"}]))

    def test_unpadded_whitespace_rejected(self):
        with self.assertRaises(ValueError):
            triage.validate(event(packages=[{"name": " mesa", "from": "1", "to": "2"}]))

    def test_revision_shape_enforced(self):
        with self.assertRaises(ValueError):
            triage.validate(event(revision="../escape"))
        with self.assertRaises(ValueError):
            triage.validate(event(revision=""))


class IngestTests(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        (self.home / "owner-marker").write_text("x")
        os.chmod(self.home, 0o755)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.home, ignore_errors=True)

    def test_ingest_stores_receipt_and_inbox(self):
        raw = json.dumps(event()).encode()
        ack = triage.ingest(self.home, raw)
        self.assertEqual(ack["event_id"], "a" * 64)
        inbox = self.home / "package-updates" / "inbox" / ("a" * 64 + ".json")
        receipt = self.home / "package-updates" / "receipts" / ("a" * 64 + ".json")
        self.assertTrue(inbox.exists())
        self.assertTrue(receipt.exists())
        self.assertEqual(json.loads(inbox.read_text())["host"], "alpha")

    def test_reingest_identical_is_idempotent(self):
        raw = json.dumps(event()).encode()
        triage.ingest(self.home, raw)
        triage.ingest(self.home, raw)
        inbox = list((self.home / "package-updates" / "inbox").glob("*.json"))
        self.assertEqual(len(inbox), 1)

    def test_reingest_same_id_different_content_rejected(self):
        triage.ingest(self.home, json.dumps(event()).encode())
        with self.assertRaises(ValueError):
            triage.ingest(self.home, json.dumps(event(revision="other")).encode())


class GateTests(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())

    def tearDown(self):
        import shutil
        shutil.rmtree(self.home, ignore_errors=True)

    def job(self, last_run_at=0, last_status="ok", last_error=None, last_delivery_error=None):
        return {"last_run_at": last_run_at, "last_status": last_status,
                "last_error": last_error, "last_delivery_error": last_delivery_error}

    def gate_once(self, event_payload=None, job=None, now=1000):
        result = triage.gate(self.home, {}, job or self.job(), now=now)
        if event_payload is not None:
            triage.ingest(self.home, json.dumps(event_payload).encode())
            result = triage.gate(self.home, {}, job or self.job(), now=now)
        return result

    def test_ingested_event_wakes_agent_with_packages(self):
        triage.ingest(self.home, json.dumps(event()).encode())
        result = triage.gate(self.home, {}, self.job(), now=1000)
        self.assertTrue(result["wakeAgent"])
        self.assertEqual(len(result["investigate"]), 1)
        upgrade = result["investigate"][0]
        self.assertEqual(upgrade["host"], "alpha")
        self.assertEqual({p["name"] for p in upgrade["packages"]}, {"mesa", "firefox"})

    def test_dispatched_failure_retries_with_backoff(self):
        triage.ingest(self.home, json.dumps(event()).encode())
        first = triage.gate(self.home, {}, self.job(last_run_at=100), now=1000)
        self.assertTrue(first["wakeAgent"])
        # The reported job failed: the incident must return to pending with a
        # retry delay (now + 900 at minimum), not be marked reported.
        during_backoff = triage.gate(self.home, {}, self.job(last_run_at=200, last_error="boom"), now=1100)
        self.assertFalse(during_backoff["wakeAgent"], "backoff must defer the retry")
        after = triage.gate(self.home, {}, self.job(last_run_at=300, last_error="boom"), now=2000)
        self.assertTrue(after["wakeAgent"], "failed delivery must retry after the backoff")

    def test_successful_dispatch_reports_and_deduplicates(self):
        triage.ingest(self.home, json.dumps(event()).encode())
        triage.gate(self.home, {}, self.job(last_run_at=100), now=1000)
        # The next run observes the completed dispatch: reported, not re-selected.
        done = triage.gate(self.home, {}, self.job(last_run_at=200), now=2000)
        self.assertFalse(done["wakeAgent"])
        state = json.loads((self.home / "package-updates" / "state.json").read_text())
        incident = next(iter(state["incidents"].values()))
        self.assertEqual(incident["status"], "reported")
        # A new event with the same upgrade set deduplicates by fingerprint.
        triage.ingest(self.home, json.dumps(event(identity="b", timestamp_us=1791600000000000)).encode())
        later = triage.gate(self.home, {}, self.job(last_run_at=300), now=3000)
        self.assertFalse(later["wakeAgent"])

    def test_fingerprint_ignores_revision(self):
        # The stated policy is deduplication by host and upgrade set. The same
        # upgrade arriving in a later deployment revision must not research twice.
        first = event(identity="a", revision="26.11.20261010.aaa")
        second = event(identity="b", revision="26.11.20261017.bbb", timestamp_us=1791700000000000)
        self.assertEqual(triage.fingerprint(first), triage.fingerprint(second))
        triage.ingest(self.home, json.dumps(first).encode())
        triage.gate(self.home, {}, self.job(last_run_at=100), now=1000)
        triage.gate(self.home, {}, self.job(last_run_at=200), now=2000)
        triage.ingest(self.home, json.dumps(second).encode())
        again = triage.gate(self.home, {}, self.job(last_run_at=300), now=3000)
        self.assertFalse(again["wakeAgent"])

    def test_different_upgrade_set_is_not_deduplicated(self):
        triage.ingest(self.home, json.dumps(event(identity="a")).encode())
        triage.gate(self.home, {}, self.job(last_run_at=100), now=1000)
        triage.gate(self.home, {}, self.job(last_run_at=200), now=2000)
        other = event(identity="c", packages=[{"name": "firefox", "from": "150.0", "to": "151.0"}])
        triage.ingest(self.home, json.dumps(other).encode())
        result = triage.gate(self.home, {}, self.job(last_run_at=300), now=3000)
        self.assertTrue(result["wakeAgent"])
        self.assertEqual({p["name"] for p in result["investigate"][0]["packages"]}, {"firefox"})

    def test_known_waits_suppress_and_recover(self):
        triage.ingest(self.home, json.dumps(event()).encode())
        key = triage.fingerprint(triage.decode(json.dumps(event())))
        suppressed = triage.gate(self.home, {key: "already discussed"}, self.job(), now=1000)
        self.assertFalse(suppressed["wakeAgent"])
        state = json.loads((self.home / "package-updates" / "state.json").read_text())
        incident = next(iter(state["incidents"].values()))
        self.assertEqual(incident["status"], "suppressed")
        recovered = triage.gate(self.home, {}, self.job(), now=2000)
        self.assertTrue(recovered["wakeAgent"])

    def test_malformed_event_rejected_to_rejected_dir(self):
        triage.private_dir(self.home / "package-updates")
        triage.private_dir(self.home / "package-updates" / "inbox")
        bad = self.home / "package-updates" / "inbox" / ("c" * 64 + ".json")
        bad.write_text('{"schema_version": 9}')
        result = triage.gate(self.home, {}, self.job(), now=1000)
        self.assertFalse(result["wakeAgent"])
        self.assertFalse(bad.exists())
        self.assertTrue((self.home / "package-updates" / "rejected" / bad.name).exists())


if __name__ == "__main__":
    unittest.main()
