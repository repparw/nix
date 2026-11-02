"""Test automatic, capacity-guarded Claro Restic replication."""

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
cmd = sys.argv[1]
if cmd == "lsf":
    state = os.environ.get("REMOTE_STATE", "empty")
    if state == "existing":
        print("config")
        print("keys/")
    elif state == "partial":
        print("keys/")
elif cmd == "about":
    if os.environ.get("FREE_QUOTA") == "unknown":
        print("{}")
    else:
        print(json.dumps({"free": int(os.environ.get("FREE_QUOTA", str(80 * 1024**3)))}))
elif cmd == "size":
    print(json.dumps({"bytes": int(os.environ.get("SOURCE_SIZE", str(30 * 1024**3)))}))
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
            ["rclone", "about", "claro:", "--json"],
            ["rclone", "size", "gd-crypt:restic/pi", "--json"],
        ])

    def test_first_run_initializes_and_copies_without_manual_step(self):
        self.assertEqual(self.run_mode("copy").returncode, 0)
        calls = self.calls()
        self.assertEqual([x[0] for x in calls], [
            "rclone", "rclone", "rclone", "rclone",
            "restic", "restic", "restic", "restic", "restic",
        ])
        self.assertEqual([x[1] for x in calls[:4]], ["mkdir", "lsf", "about", "size"])
        self.assertIn("init", calls[4])
        self.assertIn("--copy-chunker-params", calls[4])
        self.assertIn("rclone:gd-crypt:restic/pi", calls[4])
        self.assertIn("rclone:claro:restic-replica/pi", calls[4])
        self.assertIn("copy", calls[5])
        self.assertIn("--limit-upload=2048", calls[5])
        self.assertIn("check", calls[6])
        self.assertIn("forget", calls[7])
        self.assertIn("rclone.connections=2", calls[7])
        self.assertIn("--limit-upload=2048", calls[7])
        self.assertIn("--keep-monthly", calls[7])
        self.assertIn("check", calls[8])

    def test_existing_repo_only_copies_without_reinitialization(self):
        self.assertEqual(self.run_mode("copy", REMOTE_STATE="existing").returncode, 0)
        calls = self.calls()
        self.assertEqual([x[1] for x in calls[:2]], ["mkdir", "lsf"])
        self.assertFalse(any("init" in x for x in calls))
        self.assertTrue(any("copy" in x for x in calls))

    def test_no_space_refuses_initialization(self):
        result = self.run_mode("copy", FREE_QUOTA=str(31 * 1024**3),
                               SOURCE_SIZE=str(31 * 1024**3))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("insufficient space", result.stderr)
        self.assertFalse(any(x[0] == "restic" for x in self.calls()))

    def test_missing_quota_refuses_initialization(self):
        self.assertNotEqual(self.run_mode("copy", FREE_QUOTA="unknown").returncode, 0)
        self.assertFalse(any(x[0] == "restic" for x in self.calls()))

    def test_partial_repo_is_not_overwritten(self):
        self.assertNotEqual(self.run_mode("copy", REMOTE_STATE="partial").returncode, 0)
        self.assertFalse(any(x[0] == "restic" for x in self.calls()))

    def test_copy_failure_skips_checks_and_prune(self):
        self.assertNotEqual(self.run_mode("copy", REMOTE_STATE="existing", FAIL_COMMAND="copy").returncode, 0)
        self.assertFalse(any("check" in x or "forget" in x for x in self.calls()))

    def test_check_failure_skips_prune(self):
        self.assertNotEqual(self.run_mode("copy", REMOTE_STATE="existing", FAIL_COMMAND="check").returncode, 0)
        self.assertFalse(any("forget" in x for x in self.calls()))

    def test_no_retention_skips_prune(self):
        self.assertEqual(self.run_mode("copy", REMOTE_STATE="existing", RESTIC_RETENTION_ARGS="").returncode, 0)
        self.assertFalse(any("forget" in x for x in self.calls()))

    def test_invalid_command_does_not_touch_remote(self):
        self.assertNotEqual(self.run_mode("bad").returncode, 0)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
