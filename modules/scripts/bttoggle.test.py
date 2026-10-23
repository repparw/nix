import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(sys.argv.pop(1)).resolve()
MOCK = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ["BT_STATE"])
s = json.loads(p.read_text())
args = sys.argv[1:]
if args[0] == "info":
    print("Connected: " + ("yes" if s["connected"] else "no"))
    print("Blocked: " + ("yes" if s["blocked"] else "no"))
elif args[0] == "connect":
    if os.environ.get("FAIL_STAGE") == ("audio" if len(args) == 3 else "device"):
        print("Failed to connect: test transport failure")
        sys.exit(1)
    s["connected"] = True
elif args[0] == "disconnect":
    s["connected"] = False
elif args[0] in ("block", "unblock"):
    s["blocked"] = args[0] == "block"
p.write_text(json.dumps(s))
'''


class BluetoothToggle(unittest.TestCase):
    def run_toggle(self, action, *, connected=False, blocked=False, fail=""):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state.json"
            state.write_text(json.dumps(dict(connected=connected, blocked=blocked)))
            for name, text in {
                "bluetoothctl": MOCK.replace("/usr/bin/env python3", sys.executable),
                "sleep": "#!/bin/sh\nexit 0\n",
            }.items():
                executable = root / name
                executable.write_text(text)
                executable.chmod(0o755)
            result = subprocess.run(
                ["bash", "-euo", "pipefail", str(SOURCE), action],
                env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}",
                     "TOGGLE_BT_DEVICE": "00:11:22:33:44:55", "BT_STATE": str(state),
                     "FAIL_STAGE": fail},
                capture_output=True, text=True, timeout=30,
            )
            return result, json.loads(state.read_text())

    def test_failed_connection_remains_unblocked(self):
        for stage in ("device", "audio"):
            with self.subTest(stage=stage):
                result, state = self.run_toggle("connect", blocked=True, fail=stage)
                self.assertEqual(result.returncode, 3)
                self.assertFalse(state["blocked"])
                self.assertIn("test transport failure", result.stdout + result.stderr)

    def test_toggle_recovers_connected_but_blocked_device(self):
        result, state = self.run_toggle("toggle", connected=True, blocked=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state, dict(connected=True, blocked=False))

    def test_intentional_disconnect_blocks_autoconnect(self):
        for action in ("disconnect", "toggle"):
            with self.subTest(action=action):
                result, state = self.run_toggle(action, connected=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(state, dict(connected=False, blocked=True))

    def test_connect_unblocks_and_connects(self):
        result, state = self.run_toggle("connect", blocked=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state, dict(connected=True, blocked=False))


if __name__ == "__main__":
    unittest.main()
