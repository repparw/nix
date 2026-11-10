"""Exercise the real free-model watcher with stubbed opencode and Discord."""

import json
import os
from pathlib import Path
import shlex
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


def instance(ids):
    """A /api/model snapshot in the shape the watcher consumes."""
    return {"data": [{"id": i, "enabled": True, "status": "active"} for i in ids]}


INSTANCE = instance((
    "nous-portal/one:free",
    "nous-portal/two:free",
    "opencode/model-a-free",
    "opencode/model-b-free",
    "opencode/model-paid-one",
))
INSTANCE_NEW = instance((
    "nous-portal/one:free",
    "nous-portal/three:free",
    "opencode/model-a-free",
    "opencode/model-b-free",
    "opencode/model-newthing-free",
))
INSTANCE_LOST = instance(("opencode/model-a-free",))
BASELINE = ["nous-portal/one:free", "nous-portal/two:free", "opencode/model-a-free", "opencode/model-b-free"]

OPENCODE = """#!/usr/bin/env bash
case "$*" in
  *"/api/model"*)
    [ -r "$INSTANCE_FIXTURE" ] || exit 7
    cat "$INSTANCE_FIXTURE" ;;
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
        for name, text in (("opencode", OPENCODE), ("discord-notify", NOTIFY)):
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
            "INSTANCE_FIXTURE": str(self.root / "absent"),
            "OPENCODE_BIN": str(self.root / "bin" / "opencode"),
            "OPENCODE_HOME": str(self.root),
            # Keep the unavailable-catalog retry instant in tests.
            "RETRY_SECS": "0",
        }

    def fixture(self, payload):
        path = self.root / "instance.json"
        path.write_text(json.dumps(payload))
        self.env["INSTANCE_FIXTURE"] = str(path)

    def run_watch(self, *, fail_post=False):
        env = self.env | {"FAIL_POST": "1" if fail_post else "0"}
        return subprocess.run(["bash", str(self.script())], env=env, capture_output=True, text=True)

    def script(self):
        path = self.root / "watcher.sh"
        path.write_text(BODY)
        return path

    def actions(self):
        return [line for line in self.calls.read_text().splitlines() if line]

    def snapshot(self):
        return (Path(self.env["STATE_DIRECTORY"]) / "instance-free.list").read_text()

    def test_first_run_records_baseline_without_notifying(self):
        self.fixture(INSTANCE)
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("baseline recorded", result.stdout)
        self.assertEqual(self.actions(), [])
        self.assertEqual(self.snapshot().splitlines(), BASELINE)

    def test_appearance_and_disappearance_notify(self):
        self.fixture(INSTANCE)
        self.assertEqual(self.run_watch().returncode, 0)

        self.fixture(INSTANCE_NEW)
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        posts = [line for line in self.actions() if line.startswith("post ")]
        self.assertEqual(len(posts), 1)
        self.assertIn("free-model catalog changed on test-host", posts[0])
        self.assertIn("new: nous-portal/three:free, opencode/model-newthing-free", posts[0])
        self.assertIn("gone: nous-portal/two:free", posts[0])
        self.assertEqual(
            (Path(self.env["STATE_DIRECTORY"]) / ".free-models.msgid").read_text().strip(),
            "msg-1",
        )

        self.fixture(INSTANCE_LOST)
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        posts = [line for line in self.actions() if line.startswith("post ")]
        self.assertEqual(len(posts), 2)
        self.assertIn("gone: nous-portal/one:free", posts[1])
        self.assertIn("nous-portal/three:free", posts[1])
        self.assertIn("opencode/model-b-free", posts[1])
        self.assertIn("opencode/model-newthing-free", posts[1])
        self.assertEqual(
            (Path(self.env["STATE_DIRECTORY"]) / ".free-models.msgid").read_text().strip(),
            "msg-2",
        )
        # A superseded notice is deleted, not stacked.
        self.assertEqual(self.actions()[1], "delete msg-1")

    def test_unchanged_catalog_is_silent(self):
        self.fixture(INSTANCE)
        self.assertEqual(self.run_watch().returncode, 0)
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no free-model catalog change", result.stdout)
        self.assertEqual([line for line in self.actions() if line.startswith(("post", "delete"))], [])

    def test_catalog_diff_uses_the_snapshot_collation(self):
        for locale in ("C", "en_US.UTF-8"):
            with self.subTest(locale=locale):
                self.env["LC_ALL"] = locale
                sorted_names = subprocess.run(
                    ["sort"], input="nous-portal/Z:free\nnous-portal/a:free\n", env=self.env,
                    capture_output=True, text=True, check=True,
                )
                self.assertEqual(
                    sorted_names.stdout,
                    "nous-portal/Z:free\nnous-portal/a:free\n" if locale == "C"
                    else "nous-portal/a:free\nnous-portal/Z:free\n",
                )
                self.env["STATE_DIRECTORY"] = str(self.root / locale)
                self.calls.write_text("")
                self.fixture(instance(("nous-portal/Z:free", "nous-portal/a:free")))
                baseline = self.run_watch()
                self.assertEqual(baseline.returncode, 0, baseline.stderr)
                self.fixture(instance(("nous-portal/Z:free", "nous-portal/b:free")))
                result = self.run_watch()
                self.assertEqual(result.returncode, 0, result.stderr)
                posts = [line for line in self.actions() if line.startswith("post ")]
                self.assertEqual(len(posts), 1)
                self.assertIn("new: nous-portal/b:free; gone: nous-portal/a:free", posts[0])
                self.assertNotIn("Z:free", posts[0])
                self.assertEqual(
                    (Path(self.env["STATE_DIRECTORY"]) / "instance-free.list").read_text(),
                    "nous-portal/Z:free\nnous-portal/b:free\n",
                )

    def test_ambient_host_locale_cannot_break_the_diff(self):
        """The unit inherits the host locale without LC_ALL (alpha runs with
        LANG=en_IE.UTF-8, LC_MONETARY=es_AR.UTF-8), while every snapshot is
        recorded in C order. comm settles "sorted" using the collation of the
        locale it is handed, so under a host locale a C-collated snapshot is
        reported as "not in sorted order" and the service fails every run."""

        for lang in ("en_IE.UTF-8", "en_US.UTF-8", "es_AR.UTF-8"):
            with self.subTest(lang=lang):
                for var in ("LC_ALL", "LC_COLLATE", "LANGUAGE"):
                    self.env.pop(var, None)
                self.env["LANG"] = lang
                self.env["LC_MONETARY"] = "es_AR.UTF-8"
                self.env["STATE_DIRECTORY"] = str(self.root / f"ambient-{lang}")
                self.calls.write_text("")
                self.fixture(instance(("opencode/Z-free", "opencode/a-free", "opencode/b-free")))
                baseline = self.run_watch()
                self.assertEqual(baseline.returncode, 0, baseline.stderr)
                self.fixture(instance(("opencode/Z-free", "opencode/b-free")))
                result = self.run_watch()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("not in sorted order", result.stderr)
                posts = [line for line in self.actions() if line.startswith("post ")]
                self.assertEqual(len(posts), 1)
                self.assertIn("gone: opencode/a-free", posts[0])
                self.assertNotIn("Z-free", posts[0])
                self.assertEqual(
                    (Path(self.env["STATE_DIRECTORY"]) / "instance-free.list").read_text(),
                    "opencode/Z-free\nopencode/b-free\n",
                )

    def test_large_catalog_change_keeps_the_notification_bounded(self):
        self.fixture(INSTANCE)
        self.assertEqual(self.run_watch().returncode, 0)
        self.fixture(instance([f"opencode/{'long-name-' * 15}{n:04}-free" for n in range(1000)]))
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        posts = [line for line in self.actions() if line.startswith("post ")]
        self.assertEqual(len(posts), 1)
        self.assertLessEqual(len(posts[0]), 2000)

    def test_endpoint_failure_keeps_previous_snapshot(self):
        self.fixture(INSTANCE)
        self.assertEqual(self.run_watch().returncode, 0)

        Path(self.env["INSTANCE_FIXTURE"]).unlink()
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("instance-free catalog unavailable", result.stderr)
        self.assertEqual(self.snapshot().splitlines(), BASELINE)
        self.assertEqual([line for line in self.actions() if line.startswith("post")], [])

    def test_truncated_catalog_is_not_mistaken_for_removals(self):
        """The CLI intermittently cuts its JSON mid-body. jq streams, so a
        truncated document would still emit a partial id list; a snapshot
        must never be built from one."""
        self.fixture(INSTANCE)
        self.assertEqual(self.run_watch().returncode, 0)

        valid = json.dumps(INSTANCE_NEW)
        # Cut mid-record: the surviving prefix still parses as far as
        # "nous-portal/three:free" under a streaming parser.
        truncated = valid[: valid.index("opencode/model-newthing-free") - 2]
        path = self.root / "truncated.json"
        path.write_text(truncated)
        self.env["INSTANCE_FIXTURE"] = str(path)

        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("instance-free catalog unavailable", result.stderr)
        self.assertEqual(self.snapshot().splitlines(), BASELINE)
        self.assertEqual([line for line in self.actions() if line.startswith("post")], [])

    def test_truncated_catalog_recovers_after_a_good_retry(self):
        """Retries within the same run answer with the full catalog, so one
        truncated response does not push the update out by a full interval."""
        self.fixture(INSTANCE)
        self.assertEqual(self.run_watch().returncode, 0)

        valid = json.dumps(INSTANCE_NEW)
        truncated = valid[: valid.index("opencode/model-newthing-free") - 2]
        count_file = self.root / "flaky-count"
        stub = self.root / "bin" / "flaky-opencode"
        stub.write_text(f"""#!/usr/bin/env bash
count=$(cat {count_file} 2>/dev/null || echo 0)
count=$((count + 1))
echo $count > {count_file}
if [ "$count" = 1 ]; then
  printf '%s' {shlex.quote(truncated)}
  exit 0
fi
cat "$INSTANCE_FIXTURE"
""".replace("#!/usr/bin/env bash", f"#!{shutil.which('bash')}"))
        stub.chmod(0o755)
        self.fixture(INSTANCE_NEW)
        self.env["OPENCODE_BIN"] = str(stub)

        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        posts = [line for line in self.actions() if line.startswith("post ")]
        self.assertEqual(len(posts), 1, result.stdout + result.stderr)
        self.assertIn("opencode/model-newthing-free", posts[0])
        self.assertIn("opencode/model-newthing-free", self.snapshot())

    def test_post_failure_leaves_state_without_msgid(self):
        self.fixture(INSTANCE)
        self.assertEqual(self.run_watch().returncode, 0)

        self.fixture(INSTANCE_NEW)
        result = self.run_watch(fail_post=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("announcing the catalog change failed", result.stderr)
        self.assertFalse((Path(self.env["STATE_DIRECTORY"]) / ".free-models.msgid").exists())
        self.assertEqual(self.snapshot().splitlines(), BASELINE)
        # A retry once Discord answers again announces the same change.
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len([line for line in self.actions() if line.startswith("post")]), 2)
        self.assertIn("model-newthing-free", self.snapshot())


if __name__ == "__main__":
    unittest.main()
