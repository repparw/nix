"""Verify safe bootstrap, replication order and failure behavior."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(sys.argv.pop(1))


class ClaroReplicaTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.bin = root / "bin"
        self.bin.mkdir()
        self.log = root / "commands.jsonl"

        (self.bin / "restic").write_text("""#!/usr/bin/env python3
import json, os, sys
with open(os.environ["CALL_LOG"], "a") as f:
    f.write(json.dumps(["restic", *sys.argv[1:]]) + "\\n")
args = sys.argv[1:]
if os.environ.get("FAIL_COMMAND") in args:
    sys.exit(13)
""")
        (self.bin / "rclone").write_text("""#!/usr/bin/env python3
import json, os, sys
with open(os.environ["CALL_LOG"], "a") as f:
    f.write(json.dumps(["rclone", *sys.argv[1:]]) + "\\n")
""")
        for executable in self.bin.iterdir():
            executable.chmod(0o755)

        self.env = dict(os.environ)
        self.env.update({
            "PATH": str(self.bin) + os.pathsep + self.env["PATH"],
            "CALL_LOG": str(self.log),
            "RCLONE_BIN": "rclone",
            "RESTIC_REPOSITORY": "rclone:claro:restic-replica/pi",
            "RESTIC_FROM_REPOSITORY": "rclone:gd-crypt:restic/pi",
            "RESTIC_PASSWORD_FILE": "/run/secrets/resticPassword",
            "RESTIC_RETENTION_ARGS": "--keep-daily 7 --keep-weekly 4 --keep-monthly 12",
            "RESTIC_RCLONE_CONNECTIONS": "1",
            "RESTIC_UPLOAD_LIMIT_KIB": "2048",
        })

    def run_mode(self, mode, **overrides):
        return subprocess.run(
            ["bash", str(SCRIPT), mode],
            env=self.env | overrides,
            check=False,
            capture_output=True,
            text=True,
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_preflight_is_read_only(self):
        self.assertEqual(self.run_mode("preflight").returncode, 0)
        self.assertEqual(self.calls(), [
            ["rclone", "about", "claro:"],
            ["rclone", "size", "gd-crypt:restic/pi"],
        ])

    def test_init_preserves_source_chunking_parameters(self):
        self.assertEqual(self.run_mode("init").returncode, 0)
        calls = self.calls()
        self.assertEqual(len(calls), 1)
        args = calls[0]
        self.assertEqual(args[0], "restic")
        self.assertIn("init", args)
        self.assertIn("--copy-chunker-params", args)
        self.assertIn("rclone:claro:restic-replica/pi", args)
        self.assertIn("rclone:gd-crypt:restic/pi", args)
        self.assertIn("rclone.connections=1", args)
        self.assertNotIn("--limit-upload=2048", args)

    def test_copy_checks_before_pruning(self):
        self.assertEqual(self.run_mode("copy").returncode, 0)
        calls = self.calls()
        self.assertEqual(len(calls), 3)
        self.assertTrue(any(x == "copy" for x in calls[0]))
        self.assertTrue(any(x == "check" for x in calls[1]))
        self.assertTrue(any(x == "forget" for x in calls[2]))
        self.assertIn("--from-password-file", calls[0])
        self.assertIn("--limit-upload=2048", calls[0])
        self.assertIn("--limit-upload=2048", calls[2])
        self.assertIn("--keep-monthly", calls[2])

    def test_copy_failure_skips_check_and_prune(self):
        self.assertNotEqual(self.run_mode("copy", FAIL_COMMAND="copy").returncode, 0)
        self.assertEqual(len(self.calls()), 1)

    def test_check_failure_skips_prune(self):
        self.assertNotEqual(self.run_mode("copy", FAIL_COMMAND="check").returncode, 0)
        self.assertEqual(len(self.calls()), 2)

    def test_no_retention_skips_prune(self):
        self.assertEqual(self.run_mode("copy", RESTIC_RETENTION_ARGS="").returncode, 0)
        self.assertEqual(len(self.calls()), 2)

    def test_invalid_command_does_not_touch_remote(self):
        self.assertNotEqual(self.run_mode("bad").returncode, 0)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
