#!/usr/bin/env python3
"""Regression tests for the Browse MCP lazy Helium launcher."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

WRAPPER = Path(os.environ.get("BROWSE_MCP_LAZY_SCRIPT", Path(__file__).with_name("browse-mcp-lazy.py")))


class LazyBrowseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.marker = self.root / "helium-started"
        self.browse = self.root / "browse"
        self.browse.write_text(
            f"#!{sys.executable}\n"
            "import json, os, pathlib, sys\n"
            "marker = pathlib.Path(os.environ['BROWSE_HELIUM_TEST_MARKER'])\n"
            "if sys.argv[1] == 'mcp':\n"
            "    for line in sys.stdin.buffer: sys.stdout.buffer.write(line); sys.stdout.buffer.flush()\n"
            "elif sys.argv[1] == 'status':\n"
            "    print(json.dumps({'extension': {'connected': marker.exists()}}))\n"
            "elif sys.argv[1] == 'settings':\n"
            "    print('{}')\n"
        )
        self.browse.chmod(0o755)
        self.helium = self.root / "helium"
        self.helium.write_text(
            f"#!{sys.executable}\n"
            "import os, pathlib\n"
            "pathlib.Path(os.environ['BROWSE_HELIUM_TEST_MARKER']).touch()\n"
        )
        self.helium.chmod(0o755)
        self.pgrep = self.root / "pgrep"
        self.pgrep.write_text(f"#!{sys.executable}\nimport sys\nsys.exit(1)\n")
        self.pgrep.chmod(0o755)

    def run_requests(self, *messages):
        env = os.environ.copy()
        env["XDG_RUNTIME_DIR"] = str(self.root)
        env["BROWSE_HELIUM_TEST_MARKER"] = str(self.marker)
        request = b"".join(json.dumps(msg).encode() + b"\n" for msg in messages)
        result = subprocess.run(
            [sys.executable, str(WRAPPER), str(self.browse), str(self.helium), str(self.pgrep)],
            input=request, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(result.stdout, request)

    def test_initialize_and_status_do_not_start_browser(self):
        self.run_requests(
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "status", "arguments": {}}},
        )
        self.assertFalse(self.marker.exists())

    def test_browser_tool_starts_helium(self):
        self.run_requests(
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "session_new", "arguments": {}}},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "execute", "arguments": {}}},
        )
        self.assertTrue(self.marker.exists())

    def test_unrelated_request_remains_untouched(self):
        self.run_requests({"jsonrpc": "2.0", "id": 5, "method": "tools/list", "params": {}})
        self.assertFalse(self.marker.exists())


if __name__ == "__main__":
    unittest.main()
