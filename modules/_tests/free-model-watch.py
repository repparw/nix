"""Exercise the real free-model watcher with stubbed curl and Discord."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(sys.argv.pop(1)).read_text()

# writeShellApplication prepends a shebang, `set -o` lines, and a PATH export
# that would shadow the stubs. Drop everything up to and including that
# export line; the harness supplies its own PATH.
LINES = SCRIPT.splitlines()
CUT = next(i for i, line in enumerate(LINES) if line.startswith("export PATH=")) + 1
BODY = "set -euo pipefail\n" + "\n".join(LINES[CUT:])

OPENCODE = {"data": [{"id": f"model-{n}"} for n in ("a-free", "b-free", "paid-one")]}
OPENCODE_NEW = {"data": [{"id": f"model-{n}"} for n in ("a-free", "b-free", "newthing-free")]}
OPENCODE_LOST = {"data": [{"id": "model-a-free"}]}
NOUS = {"freeRecommendedModels": [{"modelName": m} for m in ("one:free", "two:free")]}
NOUS_NEW = {"freeRecommendedModels": [{"modelName": m} for m in ("one:free", "three:free")]}

CURL = """#!/usr/bin/env bash
url="${@: -1}"
case "$url" in
  *opencode.ai*)
    [ -r "$OPENCODE_FIXTURE" ] || exit 7
    cat "$OPENCODE_FIXTURE" ;;
  *nousresearch.com*)
    [ -r "$NOUS_FIXTURE" ] || exit 7
    cat "$NOUS_FIXTURE" ;;
  *) exit 7 ;;
esac
"""

NOTIFY = """#!/usr/bin/env bash
action="$*"
printf '%s\\n' "${action//$'\\n'/ }" >> "$CALLS"
case "$1" in
  post)
    if [ "${FAIL_POST:-0}" = 1 ]; then
      echo "discord-notify: POST failed (http 500)" >&2
      exit 1
    fi
    printf 'msg-%s\\n' "$(grep -c '^post ' "$CALLS")" ;;
esac
exit 0
"""


class FreeModelWatch(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="free-model-watch-test-"))
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.root)]))
        for name, text in (("curl", CURL), ("discord-notify", NOTIFY)):
            stub = self.root / "bin" / name
            stub.parent.mkdir(exist_ok=True)
            stub.write_text(text.replace("#!/usr/bin/env bash", f"#!{shutil.which('bash')}"))
            stub.chmod(0o755)
        self.calls = self.root / "calls"
        self.calls.touch()
        self.env = os.environ | {
            "PATH": f"{self.root / 'bin'}:{os.environ['PATH']}",
            "CALLS": str(self.calls),
            "STATE_DIRECTORY": str(self.root / "state"),
            "HOSTNAME": "test-host",
            "OPENCODE_FIXTURE": str(self.root / "absent"),
            "NOUS_FIXTURE": str(self.root / "absent"),
        }

    def fixture(self, name, payload):
        path = self.root / f"{name}.json"
        path.write_text(json.dumps(payload))
        self.env["OPENCODE_FIXTURE" if name == "opencode" else "NOUS_FIXTURE"] = str(path)

    def run_watch(self, *, fail_post=False):
        env = self.env | {"FAIL_POST": "1" if fail_post else "0"}
        return subprocess.run(["bash", str(self.script())], env=env, capture_output=True, text=True)

    def script(self):
        path = self.root / "watcher.sh"
        path.write_text(BODY)
        return path

    def actions(self):
        return [line for line in self.calls.read_text().splitlines() if line]

    def test_first_run_records_baseline_without_notifying(self):
        self.fixture("opencode", OPENCODE)
        self.fixture("nous", NOUS)
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("baseline recorded", result.stdout)
        self.assertEqual(self.actions(), [])
        self.assertEqual(
            (Path(self.env["STATE_DIRECTORY"]) / "opencode-free.list").read_text().splitlines(),
            ["model-a-free", "model-b-free"],
        )
        self.assertEqual(
            (Path(self.env["STATE_DIRECTORY"]) / "nous-free.list").read_text().splitlines(),
            ["one:free", "two:free"],
        )

    def test_appearance_and_disappearance_notify(self):
        self.fixture("opencode", OPENCODE)
        self.fixture("nous", NOUS)
        self.assertEqual(self.run_watch().returncode, 0)

        self.fixture("opencode", OPENCODE_NEW)
        self.fixture("nous", NOUS_NEW)
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        posts = [line for line in self.actions() if line.startswith("post ")]
        self.assertEqual(len(posts), 1)
        self.assertIn("free-model catalog changed on test-host", posts[0])
        self.assertIn("new: model-newthing-free", posts[0])
        self.assertIn("new: three:free", posts[0])
        self.assertIn("gone: two:free", posts[0])
        self.assertEqual(
            (Path(self.env["STATE_DIRECTORY"]) / ".free-models.msgid").read_text().strip(),
            "msg-1",
        )

        self.fixture("opencode", OPENCODE_LOST)
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        posts = [line for line in self.actions() if line.startswith("post ")]
        self.assertEqual(len(posts), 2)
        self.assertIn("gone: model-b-free", posts[1])
        self.assertEqual(
            (Path(self.env["STATE_DIRECTORY"]) / ".free-models.msgid").read_text().strip(),
            "msg-2",
        )
        # A superseded notice is deleted, not stacked.
        self.assertEqual(self.actions()[1], "delete msg-1")

    def test_unchanged_catalog_is_silent(self):
        self.fixture("opencode", OPENCODE)
        self.fixture("nous", NOUS)
        self.assertEqual(self.run_watch().returncode, 0)
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no free-model catalog change", result.stdout)
        self.assertEqual([line for line in self.actions() if line.startswith(("post", "delete"))], [])

    def test_large_catalog_change_keeps_the_notification_bounded(self):
        self.fixture("opencode", OPENCODE)
        self.fixture("nous", NOUS)
        self.assertEqual(self.run_watch().returncode, 0)
        self.fixture("opencode", {"data": [{"id": f"{'long-name-' * 15}{n:04}-free"} for n in range(1000)]})
        self.fixture("nous", {"freeRecommendedModels": [{"modelName": f"{'long-name-' * 15}{n:04}:free"} for n in range(1000)]})
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        posts = [line for line in self.actions() if line.startswith("post ")]
        self.assertEqual(len(posts), 1)
        self.assertLessEqual(len(posts[0]), 2000)

    def test_endpoint_failure_keeps_previous_snapshot(self):
        self.fixture("opencode", OPENCODE)
        self.fixture("nous", NOUS)
        self.assertEqual(self.run_watch().returncode, 0)

        Path(self.env["NOUS_FIXTURE"]).unlink()
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("nous-free catalog unavailable", result.stderr)
        self.assertIn("opencode-free unchanged", result.stdout)
        self.assertEqual(
            (Path(self.env["STATE_DIRECTORY"]) / "nous-free.list").read_text().splitlines(),
            ["one:free", "two:free"],
        )
        self.assertEqual([line for line in self.actions() if line.startswith("post")], [])

    def test_post_failure_leaves_state_without_msgid(self):
        self.fixture("opencode", OPENCODE)
        self.fixture("nous", NOUS)
        self.assertEqual(self.run_watch().returncode, 0)

        self.fixture("opencode", OPENCODE_NEW)
        result = self.run_watch(fail_post=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("announcing the catalog change failed", result.stderr)
        self.assertFalse((Path(self.env["STATE_DIRECTORY"]) / ".free-models.msgid").exists())
        self.assertEqual(
            (Path(self.env["STATE_DIRECTORY"]) / "opencode-free.list").read_text().splitlines(),
            ["model-a-free", "model-b-free"],
        )
        # A retry once Discord answers again announces the same change.
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len([line for line in self.actions() if line.startswith("post")]), 2)
        self.assertIn("model-newthing-free", (Path(self.env["STATE_DIRECTORY"]) / "opencode-free.list").read_text())


if __name__ == "__main__":
    unittest.main()
