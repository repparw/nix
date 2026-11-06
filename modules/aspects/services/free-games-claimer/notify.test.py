"""Exercise notification batching, replay, and generic service failures."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent


class NotifyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = Path(self.tmp.name) / "state"
        (self.state / "data").mkdir(parents=True)
        (self.state / "logs").mkdir()
        self.bin = Path(self.tmp.name) / "bin"
        self.bin.mkdir()
        fake = self.bin / "discord-notify"
        fake.write_text(
            '#!/usr/bin/env bash\n'
            'if [ "${NOTIFY_FAIL:-0}" = 1 ]; then exit 1; fi\n'
            'printf "%s\\0" "$2" >> "$NOTIFY_OUTPUT"\n'
        )
        fake.chmod(0o755)
        self.log = Path(self.tmp.name) / "messages"
        for store in ("epic-games", "gog"):
            (self.state / "logs" / f"{store}.status").write_text("0\n")
            (self.state / "logs" / f"{store}.log").write_text("ok\n")

    def run_notify(self, fail=False, service_result="success"):
        env = os.environ.copy()
        env.update({
            "PATH": str(self.bin) + os.pathsep + env["PATH"],
            "FGC_STATE_DIR": str(self.state),
            "FGC_CLAIM_DIFF": str(ROOT / "claim-diff.jq"),
            "NOTIFY_OUTPUT": str(self.log),
            "NOTIFY_FAIL": "1" if fail else "0",
            "SERVICE_RESULT": service_result,
        })
        return subprocess.run(
            ["bash", str(ROOT / "notify.sh")],
            env=env, text=True, capture_output=True,
        )

    def messages(self):
        return [
            chunk.decode() for chunk in self.log.read_bytes().split(b"\0") if chunk
        ] if self.log.exists() else []

    def test_many_claims_are_batched_without_losing_state(self):
        games = {
            f"game-{i}": {
                "title": f"Game {i}", "url": "https://example.com/game", "status": "claimed"
            }
            for i in range(75)
        }
        (self.state / "data" / "epic-games.json").write_text(json.dumps({"me": games}))
        result = self.run_notify()
        self.assertEqual(result.returncode, 0, result.stderr)
        msgs = self.messages()
        self.assertGreater(len(msgs), 1)
        self.assertTrue(all(len(m) < 2000 for m in msgs))
        self.assertEqual(sum(m.count("✅ epic:") for m in msgs), 75)
        self.assertEqual(
            len(json.loads((self.state / "notify-state.json").read_text())), 75
        )
        second = self.run_notify()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(msgs, self.messages())

    def test_failed_delivery_is_replayed(self):
        (self.state / "data" / "gog.json").write_text(json.dumps(
            {"me": {"game": {"title": "Game", "status": "claimed"}}}
        ))
        self.assertNotEqual(self.run_notify(fail=True).returncode, 0)
        self.assertFalse((self.state / "notify-state.json").exists())
        self.assertEqual(self.run_notify().returncode, 0)
        self.assertEqual(len(self.messages()), 1)
        self.assertIn("✅ gog: Game", self.messages()[0])

    def test_store_failure_is_reported_without_json_change(self):
        (self.state / "logs" / "gog.status").write_text("1\n")
        self.assertEqual(self.run_notify(service_result="exit-code").returncode, 0)
        self.assertIn("Store gog run failed", self.messages()[0])
        self.assertIn("exit-code", self.messages()[0])


if __name__ == "__main__":
    unittest.main()
