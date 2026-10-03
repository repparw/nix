import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(sys.argv.pop(1)).resolve()
PYTHON = sys.executable
MOCK = '''#!/usr/bin/env python3
import fcntl, json, os
from pathlib import Path
import sys
root = Path(os.environ["FIXTURE"])
args = sys.argv[1:]
name = Path(sys.argv[0]).name
with (root / "calls").open("a") as log:
    log.write(json.dumps([name, *args]) + "\\n")
if name == "nix-store":
    if Path(args[-1]).name == os.environ.get("FAIL_QUERY"):
        sys.exit(1)
    print(args[-1])
    closure = root / "closures" / Path(args[-1]).name
    if closure.exists():
        print(closure.read_text())
elif name == "nix-env":
    with (root / "lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise AssertionError("generation pruning must hold the fleet lock")
    if os.environ.get("FAIL_DELETE"):
        sys.exit(1)
    profile = Path(args[1])
    for generation in args[3:]:
        profile.with_name(f"{profile.name}-{generation}-link").unlink()
elif name == "nix-collect-garbage":
    assert not args
    with (root / "lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise AssertionError("GC must hold the fleet lock")
'''


class Retention(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.profile = self.root / "profiles" / "system"
        self.profile.parent.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.root / "closures").mkdir()
        self.gcroots = self.root / "gcroots"
        self.gcroots.mkdir()
        for name in ["nix-store", "nix-env", "nix-collect-garbage"]:
            mock = self.bin / name
            mock.write_text(MOCK.replace("/usr/bin/env python3", PYTHON))
            mock.chmod(0o755)
        self.targets = {}
        for number in range(1, 9):
            target = self.root / f"system-{number}"
            target.mkdir()
            self.targets[number] = target
            self.profile.with_name(f"system-{number}-link").symlink_to(target)
        self.profile.symlink_to("system-8-link")
        self.user_generation = self.profile.with_name("user-1-link")
        self.user_generation.symlink_to(self.targets[3])
        self.current = self.root / "current"
        self.current.symlink_to(self.targets[2])
        self.booted = self.root / "booted"
        self.booted.symlink_to(self.targets[1])
        (self.gcroots / "current-system").symlink_to(self.current)
        (self.gcroots / "booted-system").symlink_to(self.booted)
        # These external roots must never be deleted by profile pruning.
        (self.gcroots / "prepared-system").symlink_to(self.targets[3])
        (self.gcroots / "previous").symlink_to(self.targets[3])
        self.env = os.environ | {"FIXTURE": str(self.root), "PATH": str(self.bin) + ":" + os.environ["PATH"]}

    def run_cli(self, mode="apply", **env):
        result = subprocess.run([
            PYTHON, str(SOURCE), mode, "--profile", str(self.profile),
            "--current", str(self.current), "--booted", str(self.booted),
            "--gcroots", str(self.gcroots), "--lock", str(self.root / "lock"),
        ], env=self.env | env, capture_output=True, text=True)
        self.calls = [json.loads(line) for line in (self.root / "calls").read_text().splitlines()] if (self.root / "calls").exists() else []
        return result

    def test_prunes_only_eligible_generation_preserving_runtime_and_other_roots(self):
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        retained = sorted(path.name for path in self.profile.parent.glob("system-*-link"))
        self.assertEqual(retained, ["system-1-link", "system-2-link", "system-4-link", "system-5-link", "system-6-link", "system-7-link", "system-8-link"])
        self.assertTrue((self.gcroots / "prepared-system").exists())
        self.assertTrue((self.gcroots / "previous").exists())
        self.assertTrue(self.user_generation.exists())
        self.assertEqual(self.calls[-1], ["nix-collect-garbage"])
        again = self.run_cli()
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(sum(call[0] == "nix-env" for call in self.calls), 1)

    def test_wrapper_containing_current_system_survives(self):
        (self.root / "closures" / "system-3").write_text(str(self.targets[2]))
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.profile.with_name("system-3-link").exists())
        self.assertFalse(any(call[0] == "nix-env" for call in self.calls))

    def test_plan_never_deletes_or_collects(self):
        result = self.run_cli("plan")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Eligible system generations: 3", result.stdout)
        self.assertTrue(self.profile.with_name("system-3-link").exists())
        self.assertTrue(all(call[0] == "nix-store" for call in self.calls))

    def test_missing_runtime_gc_root_aborts(self):
        (self.gcroots / "booted-system").unlink()
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls, [])

    def test_closure_error_aborts_before_any_pruning_or_gc(self):
        result = self.run_cli(FAIL_QUERY="system-1")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.profile.with_name("system-3-link").exists())
        self.assertTrue(all(call[0] == "nix-store" for call in self.calls))

    def test_older_selected_profile_survives(self):
        self.profile.unlink()
        self.profile.symlink_to("system-3-link")
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.profile.with_name("system-3-link").exists())
        self.assertFalse(any(call[0] == "nix-env" for call in self.calls))

    def test_failed_pruning_does_not_run_gc(self):
        result = self.run_cli(FAIL_DELETE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.profile.with_name("system-3-link").exists())
        self.assertFalse(any(call[0] == "nix-collect-garbage" for call in self.calls))

    def test_busy_deployment_lock_defers_without_pruning_or_gc(self):
        with (self.root / "lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("deferred", result.stdout)
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
