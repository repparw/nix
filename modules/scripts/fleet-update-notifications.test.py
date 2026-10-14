"""Exercise the real failure reporter under errexit/pipefail with no network."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(sys.argv.pop(1)).read_text()
STRIP = SOURCE[SOURCE.index("strip_ansi() {") : SOURCE.index("\n# Why the current")]
REPORT = SOURCE[SOURCE.index("notify_failure() {") : SOURCE.index("\nnotify_file() {")]


class Notifications(unittest.TestCase):
    def report(self, reason, log=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            secret = root / "env"
            secret.write_text("DISCORD_BOT_TOKEN=fixture\n")
            output = root / "request"
            logfile = root / "failure.log"
            if log is not None:
                logfile.write_text(log)
            script = (
                "set -euo pipefail\n"
                + STRIP
                + REPORT.replace("/run/secrets/hermes-env", str(secret))
                + '\ncurl() { printf "%s\\0" "$@" > "$TEST_OUTPUT"; }\n'
                + 'api=fixture\nfailure_reason=$TEST_REASON\n'
                + 'notify_failure "fleet deployment failed" "$TEST_LOG"\n'
            )
            env = os.environ | {
                "TEST_OUTPUT": str(output),
                "TEST_REASON": reason,
                "TEST_LOG": str(logfile),
            }
            result = subprocess.run(["bash", "-c", script], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertTrue(output.exists(), "reporter exited without sending an alert")
            args = output.read_bytes().decode().split("\0")
            if "-d" in args:
                payload = args[args.index("-d") + 1]
            else:
                payload = next(a.removeprefix("payload_json=") for a in args if a.startswith("payload_json="))
            body = json.loads(payload)["content"]
            self.assertLessEqual(len(body.encode("utf-16-le")) // 2, 2000)
            attached = any(a.startswith("files[0]=@") for a in args)
            return body, attached

    def test_log_without_error_match_still_reports(self):
        body, _ = self.report("build or activation of alpha failed", "connection refused\n")
        self.assertIn("build or activation of alpha failed", body)

    def test_preparation_failure_reports_its_build_error(self):
        body, _ = self.report("preparation of alpha failed", "error: target build failed\n")
        self.assertIn("error: target build failed", body)

    def test_many_errors_do_not_abort_on_sigpipe(self):
        body, attached = self.report("build or activation of alpha failed", "error: failed\n" * 10000)
        self.assertIn("error: failed", body)
        self.assertFalse(attached)
        self.assertEqual(body.count("error: failed"), 25)

    def test_supplementary_unicode_counts_as_two_units(self):
        body, attached = self.report("build or activation of alpha failed", "error: " + "😀" * 1500)
        self.assertIn("error:", body)
        self.assertTrue(attached)

    def test_long_reason_without_log_uses_json(self):
        body, attached = self.report("soak: " + "probe failed " * 300)
        self.assertIn("soak:", body)
        self.assertFalse(attached)

    def test_gate_failure_does_not_quote_successful_activation(self):
        body, _ = self.report("alpha activated the wrong revision", "warning: ignored error: old output\n")
        self.assertIn("alpha activated the wrong revision", body)
        self.assertNotIn("old output", body)

    def test_soak_failure_does_not_quote_activation(self):
        body, _ = self.report("soak: container@jellyfin is activating", "error: irrelevant\n")
        self.assertIn("soak: container@jellyfin", body)
        self.assertNotIn("irrelevant", body)


if __name__ == "__main__":
    unittest.main()
