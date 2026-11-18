"""Regression checks for Browse MCP guidance filtering."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("browse-mcp-lazy.py")
spec = importlib.util.spec_from_file_location("browse_mcp_lazy", SCRIPT)
browse = importlib.util.module_from_spec(spec)
spec.loader.exec_module(browse)


class GuidanceTest(unittest.TestCase):
    def rewrite(self, result):
        response = {"jsonrpc": "2.0", "id": 1, "result": result}
        return json.loads(browse.rewrite_response((json.dumps(response) + "\n").encode()))["result"]

    def test_plain_instructions(self):
        original = ('When only a person can proceed — login, 2FA, passkey, captcha or payment confirmation — '
                    'call `handoff` with the `tab` and what the user should do, and wait. '
                    'Never solve a captcha yourself and never retry-loop a blocked site.')
        guidance = self.rewrite({"instructions": original})["instructions"]
        self.assertIn("handoff", guidance)
        self.assertIn("site block", guidance)
        self.assertNotIn("Never solve", guidance)

    def test_execute_instructions(self):
        original = ('When only a person can proceed — login, 2FA, passkey, captcha or payment confirmation — '
                    'call `handoff("what the user should do")` and wait. Pass `start` for an action '
                    'that itself blocks. Never solve a captcha yourself and never retry-loop a blocked site; '
                    'if a challenge is interactive or the site refuses the visit, hand off or stop and tell the user.')
        self.assertNotIn("Never solve", self.rewrite({"instructions": original})["instructions"])

    def test_tool_list(self):
        tools = [{"name": "execute",
            "description": "Aftermath (a bot challenge: hand interactive ones to the user with handoff(), never solve or retry-loop them).",
            "inputSchema": {"properties": {"code": {"description":
                "- handoff(message, {timeoutMs?, start?}) when only the user can proceed (login, 2FA, captcha, payment); demonstrate(message) to watch the user do a flow."}}}
        }]
        tool = self.rewrite({"tools": tools})["tools"][0]
        self.assertNotIn("never solve", tool["description"])
        self.assertNotIn("when only the user", tool["inputSchema"]["properties"]["code"]["description"])

    def test_tool_response_keeps_diagnostics(self):
        text = ('Blocked by a recaptcha interactive challenge on https://example.org (iframe). '
                'Don\'t retry, reload or try to solve it: call handoff("Solve the security check on https://example.org, then click Continue") so the user does it, or stop.\n'
                'Challenge: {"vendor":"recaptcha","kind":"interactive","status":"blocked","recommendation":"handoff"} '
                '(an interactive one needs handoff(); never solve or retry-loop it)')
        result = self.rewrite({"content": [{"type": "text", "text": text}]})
        output = result["content"][0]["text"]
        self.assertIn('"vendor":"recaptcha"', output)
        self.assertIn('"status":"blocked"', output)
        self.assertIn('"recommendation":"handoff"', output)
        self.assertNotIn("never solve", output)
        self.assertNotIn("Don't retry, reload or try to solve it", output)

    def test_unrelated_messages_pass_through(self):
        for line in [b'not json\n', b'{"method":"tools/call","params":{}}\n',
                     b'{"jsonrpc":"2.0","id":4,"result":{"content":[{"type":"text","text":"CAPTCHA appears on this page."}]}}\n',
                     b'{"jsonrpc":"2.0","id":5,"error":{"message":"Something failed"}}\n']:
            self.assertEqual(browse.rewrite_response(line), line)

    def test_stdio_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory) / "browse"
            fake.write_text('#!/usr/bin/env python3\n'
                'import json,sys\n'
                'assert sys.argv[1:] == ["mcp"]\n'
                f'instructions = {browse.GUIDANCE_REWRITES[0][0]!r}\n'
                'for line in sys.stdin:\n'
                '  msg = json.loads(line)\n'
                '  print(json.dumps({"jsonrpc":"2.0","id":msg["id"],"result":{"instructions":instructions}}),flush=True)\n')
            fake.chmod(0o755)
            completed = subprocess.run([sys.executable, str(SCRIPT), str(fake), "/missing-helium", "/bin/false"],
                input=b'{"jsonrpc":"2.0","id":1,"method":"initialize"}\n',
                capture_output=True, timeout=10, check=True)
            self.assertEqual(len(completed.stdout.splitlines()), 1)
            self.assertNotIn("Never solve", completed.stdout.decode())
            self.assertIn("handoff", completed.stdout.decode())


if __name__ == "__main__":
    unittest.main()
