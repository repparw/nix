"""Run the readiness probe and deliverer against stubbed SSH and Discord."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

PROBE_SOURCE = Path(sys.argv.pop(1)).read_text()
DELIVER_SOURCE = Path(sys.argv.pop(1)).read_text()

WAITING_SONARR = "version=4.0.19.2979\nlog_read=true\nunauthorized=false\n"
READY_SONARR = "version=4.0.20.3014\nlog_read=true\nunauthorized=false\n"
SONARR_401 = "version=4.0.20.3014\nlog_read=true\nunauthorized=true\n"
SONARR_NO_PROCESS = "version=\nlog_read=true\nunauthorized=false\n"
WAITING_MOONSHINE = (
    "runtime_override=true\npersistent_override=false\ncandidate_root=true\n"
    "stream_active=true\nrunning_exe=/nix/store/candidate/bin/moonshine\n"
    "generated_exe=/nix/store/candidate/bin/moonshine\nservice_active=true\n"
)
READY_MOONSHINE = (
    "runtime_override=false\npersistent_override=false\ncandidate_root=false\n"
    "stream_active=false\nrunning_exe=/nix/store/upstream/bin/moonshine\n"
    "generated_exe=/nix/store/upstream/bin/moonshine\nservice_active=true\n"
)

SSH_STUB = """\
#!/bin/sh
if [ -f "$FIXTURE/ssh-fail" ]; then
  echo "ssh: connection refused" >&2
  exit 255
fi
cat "$FIXTURE/ssh-response"
"""

DISCORD_STUB = """\
#!/bin/sh
printf '%s\\n' "$*" >> "$FIXTURE/discord-calls"
if [ -f "$FIXTURE/discord-fails" ]; then
  exit 1
fi
echo "fixture-message-id"
"""


class Readiness(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.fix = self.root / "fixture"
        self.fix.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name, text in [("ssh", SSH_STUB), ("discord-notify", DISCORD_STUB)]:
            stub = self.bin / name
            stub.write_text(text)
            stub.chmod(0o755)
        self.env = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "FIXTURE": str(self.fix),
        }

    def write_script(self, source, token_value):
        script = self.root / "script"
        script.write_text(source.replace("@FLEET_ALPHA_ADDRESS@", token_value))
        return script

    def run_probe(self, state, watcher=None, response=None, fail=False):
        (self.fix / "ssh-fail").unlink(missing_ok=True)
        (self.fix / "ssh-response").write_text(response or "")
        if fail:
            (self.fix / "ssh-fail").write_text("1")
        arguments = [str(self.probe), "--state", str(state)]
        if watcher is not None:
            arguments += ["--watcher", watcher]
        return subprocess.run(["bash", *arguments], env=self.env, text=True, capture_output=True)

    def run_deliver(self, state):
        script = self.root / "deliver"
        script.write_text(DELIVER_SOURCE)
        return subprocess.run(
            ["bash", str(script)], env=self.env | {"FLEET_UPDATE_STATE": str(state)},
            text=True, capture_output=True,
        )

    def events(self, state):
        events = [json.loads(p.read_text()) for p in (state / "readiness-events").glob("*.json")]
        return sorted(events, key=lambda event: event["timestamp_us"])

    def last(self, state, watcher):
        return json.loads((state / "readiness" / f"last-{watcher}.json").read_text())

    def setUpProbe(self):
        self.probe = self.write_script(PROBE_SOURCE, "alpha-fixture")

    def test_usage_and_unknown_watcher_fail_closed(self):
        self.setUpProbe()
        state = self.root / "state"
        self.assertNotEqual(self.run_probe(state, watcher="nope").returncode, 0)
        self.assertNotEqual(self.run_probe(state, watcher="sonarr-jellyfin; rm -rf /").returncode, 0)

    def test_not_ready_then_ready_notifies_once_per_transition(self):
        self.setUpProbe()
        state = self.root / "state"
        result = self.run_probe(state, watcher="sonarr-jellyfin", response=WAITING_SONARR)
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events(state)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["status"], "waiting")
        self.assertEqual(events[0]["watcher"], "sonarr-jellyfin")
        self.assertIn("4.0.19.2979", events[0]["message"])
        self.assertEqual(self.last(state, "sonarr-jellyfin")["status"], "waiting")

        self.run_probe(state, watcher="sonarr-jellyfin", response=WAITING_SONARR)
        self.assertEqual(len(self.events(state)), 1, "same status must not re-notify")

        self.run_probe(state, watcher="sonarr-jellyfin", response=READY_SONARR)
        events = self.events(state)
        self.assertEqual(len(events), 2)
        self.assertEqual(events[1]["status"], "ready")
        self.assertIn("4.0.20.3014", events[1]["message"])
        self.assertIn("no 401", events[1]["message"])
        self.assertEqual(self.last(state, "sonarr-jellyfin")["status"], "ready")

        self.run_probe(state, watcher="sonarr-jellyfin", response=READY_SONARR)
        self.assertEqual(len(self.events(state)), 2)

    def test_ready_requires_running_fix_and_clean_log(self):
        self.setUpProbe()
        state = self.root / "state"
        self.run_probe(state, watcher="sonarr-jellyfin", response=SONARR_401)
        events = self.events(state)
        self.assertEqual(events[0]["status"], "waiting")
        self.assertIn("401", events[0]["message"])
        state2 = self.root / "state2"
        self.run_probe(state2, watcher="sonarr-jellyfin", response=SONARR_NO_PROCESS)
        events = self.events(state2)
        self.assertEqual(events[0]["status"], "waiting")
        self.assertIn("process not found", events[0]["message"])


    def test_sonarr_unreadable_log_cannot_be_ready(self):
        self.setUpProbe()
        state = self.root / "sonarr-missing-log"
        response = "version=4.0.20.3014\nlog_read=false\nunauthorized=false\n"
        result = self.run_probe(state, watcher="sonarr-jellyfin", response=response)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = self.events(state)[0]
        self.assertEqual(event["status"], "waiting")
        self.assertIn("unavailable", event["detail"])
        missing_401 = self.root / "sonarr-missing-401"
        result = self.run_probe(missing_401, watcher="sonarr-jellyfin",
                                response="version=4.0.20.3014\\nlog_read=true\\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(missing_401)[0]["status"], "waiting")

    def test_moonshine_ready_requires_running_generated_binary(self):
        self.setUpProbe()
        broken = [
            READY_MOONSHINE.replace("service_active=true", "service_active=false"),
            READY_MOONSHINE.replace("running_exe=/nix/store/upstream", "running_exe="),
            READY_MOONSHINE.replace("generated_exe=/nix/store/upstream", "generated_exe=/nix/store/other"),
            READY_MOONSHINE.replace("generated_exe=/nix/store/upstream/bin/moonshine\n", ""),
        ]
        for i, response in enumerate(broken):
            state = self.root / f"moonshine-bad-{i}"
            result = self.run_probe(state, watcher="moonshine-pr227-runtime", response=response)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.events(state)[0]["status"], "waiting")

    def test_unavailable_keeps_previous_status_and_resumes(self):
        self.setUpProbe()
        state = self.root / "state"
        self.run_probe(state, watcher="sonarr-jellyfin", response=WAITING_SONARR)
        self.assertEqual(len(self.events(state)), 1)

        result = self.run_probe(state, watcher="sonarr-jellyfin", fail=True)
        self.assertEqual(result.returncode, 0, "an unreachable Alpha must never fail the caller")
        self.assertIn("unavailable", result.stderr)
        self.assertEqual(len(self.events(state)), 1)
        self.assertEqual(self.last(state, "sonarr-jellyfin")["status"], "waiting")

        self.run_probe(state, watcher="sonarr-jellyfin", response=READY_SONARR)
        events = self.events(state)
        self.assertEqual(len(events), 2, "resume after failure reports the pending transition")
        self.assertEqual(events[1]["status"], "ready")

    def test_crash_after_enqueue_does_not_duplicate(self):
        self.setUpProbe()
        state = self.root / "state"
        self.run_probe(state, watcher="moonshine-pr227-runtime", response=WAITING_MOONSHINE)
        self.assertEqual(len(self.events(state)), 1)
        # Simulate a crash between enqueueing the event and writing the
        # last-status record: the replay must fail the duplicate link closed.
        (state / "readiness" / "last-moonshine-pr227-runtime.json").unlink()
        self.run_probe(state, watcher="moonshine-pr227-runtime", response=WAITING_MOONSHINE)
        events = self.events(state)
        self.assertEqual(len(events), 1, "replayed transition must not enqueue twice")
        self.assertEqual(self.last(state, "moonshine-pr227-runtime")["status"], "waiting")

    def test_moonshine_reports_override_evidence_then_clear(self):
        self.setUpProbe()
        state = self.root / "state"
        self.run_probe(state, watcher="moonshine-pr227-runtime", response=WAITING_MOONSHINE)
        events = self.events(state)
        self.assertEqual(events[0]["status"], "waiting")
        self.assertIn("runtime=true", events[0]["message"])
        self.assertIn("stream_active=true", events[0]["message"])
        self.assertEqual(events[0]["evidence"]["running_exe"], "/nix/store/candidate/bin/moonshine")

        self.run_probe(state, watcher="moonshine-pr227-runtime", response=READY_MOONSHINE)
        events = self.events(state)
        self.assertEqual(events[1]["status"], "ready")
        self.assertIn("absent from Alpha runtime", events[1]["message"])

    def test_full_pass_covers_both_watchers(self):
        self.setUpProbe()
        state = self.root / "state"
        result = self.run_probe(state, response=READY_SONARR)
        self.assertEqual(result.returncode, 0, result.stderr)
        events = {event["watcher"]: event for event in self.events(state)}
        self.assertEqual(sorted(events), ["moonshine-pr227-runtime", "sonarr-jellyfin"])
        self.assertEqual(events["sonarr-jellyfin"]["status"], "ready")
        # A response for Sonarr is not positive evidence about Moonshine.
        self.assertEqual(events["moonshine-pr227-runtime"]["status"], "waiting")

    def test_events_carry_complete_protocol(self):
        self.setUpProbe()
        state = self.root / "state"
        self.run_probe(state, watcher="sonarr-jellyfin", response=READY_SONARR)
        event = self.events(state)[0]
        self.assertEqual(event["schema_version"], 1)
        self.assertEqual(event["kind"], "readiness")
        self.assertRegex(event["event_id"], r"^[0-9a-f]{64}$")
        self.assertIsInstance(event["timestamp_us"], int)
        self.assertEqual(event["detail"], "sonarr 4.0.20.3014 running; no 401 in recent sonarr log")

    def test_deliverer_posts_once_and_acks(self):
        self.setUpProbe()
        state = self.root / "state"
        self.run_probe(state, watcher="sonarr-jellyfin", response=READY_SONARR)
        entries = sorted((state / "readiness-events").glob("*.json"))
        self.assertEqual(len(entries), 1)

        result = self.run_deliver(state)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list((state / "readiness-events").glob("*.json"))), 0)
        calls = (self.fix / "discord-calls").read_text().splitlines()
        self.assertEqual(len(calls), 1)
        self.assertIn("post", calls[0])
        self.assertIn("4.0.20.3014", calls[0])

        self.run_probe(state, watcher="sonarr-jellyfin", response=WAITING_SONARR)
        (self.fix / "discord-calls").unlink(missing_ok=True)
        (self.fix / "discord-fails").write_text("1")
        result = self.run_deliver(state)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list((state / "readiness-events").glob("*.json"))), 1,
                         "a failed post must leave the exact bytes queued")

        (self.fix / "discord-fails").unlink()
        (self.fix / "discord-calls").unlink(missing_ok=True)
        self.run_deliver(state)
        self.assertEqual(len(list((state / "readiness-events").glob("*.json"))), 0)
        self.assertEqual(len((self.fix / "discord-calls").read_text().splitlines()), 1,
                         "the retried post must happen exactly once")

    def test_three_undelivered_transitions_remain_distinct_and_ordered(self):
        self.setUpProbe()
        state = self.root / "cycle"
        for response in (WAITING_SONARR, READY_SONARR, WAITING_SONARR):
            result = self.run_probe(state, watcher="sonarr-jellyfin", response=response)
            self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events(state)
        self.assertEqual([event["status"] for event in events], ["waiting", "ready", "waiting"])
        self.assertEqual(len({event["event_id"] for event in events}), 3)
        result = self.run_deliver(state)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = (self.fix / "discord-calls").read_text().splitlines()
        self.assertEqual(len(calls), 3)
        self.assertIn("4.0.19.2979", calls[0])
        self.assertIn("4.0.20.3014", calls[1])
        self.assertIn("4.0.19.2979", calls[2])
        self.assertEqual(list((state / "readiness-events").glob("*.json")), [])

    def test_deliverer_skips_malformed_entries_without_posting(self):
        state = self.root / "state"
        (state / "readiness-events").mkdir(parents=True)
        (state / "readiness-events" / "broken.json").write_text("{not json")
        (state / "readiness-events" / "wrong.json").write_text(json.dumps({"schema_version": 2, "kind": "readiness"}))
        result = self.run_deliver(state)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list((state / "readiness-events").glob("*.json"))), 2)
        self.assertFalse((self.fix / "discord-calls").exists())


if __name__ == "__main__":
    unittest.main()
