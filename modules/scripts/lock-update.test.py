"""Exercise the lock workflow's shell step against a local Git remote."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

WORKFLOW = Path(sys.argv.pop(1)).read_text()
UPDATE = WORKFLOW.split("        run: |\n", 1)[1]
SCRIPT = "\n".join(line.removeprefix("          ") for line in UPDATE.splitlines())


class LockUpdate(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.remote = self.root / "remote.git"
        self.checkout = self.root / "checkout"
        self.git("init", "--bare", "--initial-branch=main", str(self.remote))
        self.git("clone", str(self.remote), str(self.checkout))
        self.git("config", "user.name", "fixture", cwd=self.checkout)
        self.git("config", "user.email", "fixture@example.test", cwd=self.checkout)
        (self.checkout / "flake.lock").write_text("old\n")
        self.git("add", "flake.lock", cwd=self.checkout)
        self.git("commit", "-m", "fixture", cwd=self.checkout)
        self.git("push", "origin", "main", cwd=self.checkout)
        self.main = self.git("rev-parse", "HEAD", cwd=self.checkout)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        nix = self.bin / "nix"
        nix.write_text(f"#!{shutil.which('bash')}\n" + "if [ \"$FIXTURE_CHANGE\" = 1 ]; then printf 'new\\n' > flake.lock; fi\n"
                       "if [ \"$FIXTURE_RACE\" = 1 ]; then git --git-dir=\"$FIXTURE_REMOTE\" update-ref refs/heads/automation/flake-lock \"$FIXTURE_MAIN\"; fi\n")
        nix.chmod(0o755)
        gh = self.bin / "gh"
        gh.write_text(f"#!{sys.executable}\nimport json, os, sys\nfrom pathlib import Path\n"
                      "with Path(os.environ['FIXTURE_REQUESTS']).open('a') as log:\n"
                      "    log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                      "if sys.argv[1:3] == ['pr', 'list']:\n"
                      "    print(os.environ['FIXTURE_PR'])\n")
        gh.chmod(0o755)

    def git(self, *arguments, cwd=None):
        result = subprocess.run(["git", *arguments], cwd=cwd, text=True, capture_output=True, check=True)
        return result.stdout.strip()

    def update(self, change=True, pr="", race=False):
        env = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "FIXTURE_CHANGE": str(int(change)), "FIXTURE_PR": pr,
            "FIXTURE_RACE": str(int(race)), "FIXTURE_REMOTE": str(self.remote),
            "FIXTURE_MAIN": self.main, "FIXTURE_REQUESTS": str(self.root / "requests"),
        }
        result = subprocess.run(["bash", "-c", SCRIPT], cwd=self.checkout, env=env,
                                text=True, capture_output=True)
        self.requests = [json.loads(line) for line in (self.root / "requests").read_text().splitlines()]
        self.assertEqual(self.git("--git-dir", str(self.remote), "rev-parse", "main"), self.main)
        return result

    def test_creates_lock_branch_and_pr_without_changing_main(self):
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("--git-dir", str(self.remote), "show", "automation/flake-lock:flake.lock"), "new")
        self.assertEqual(self.git("--git-dir", str(self.remote), "diff", "--name-only", "main", "automation/flake-lock"), "flake.lock")
        self.assertTrue(any(r[:2] == ["pr", "create"] for r in self.requests))

    def test_existing_pr_gets_branch_update_without_duplicate_pr(self):
        self.git("push", "origin", "HEAD:refs/heads/automation/flake-lock", cwd=self.checkout)
        result = self.update(pr="123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("--git-dir", str(self.remote), "show", "automation/flake-lock:flake.lock"), "new")
        self.assertFalse(any(r[:2] == ["pr", "create"] for r in self.requests))

    def test_no_change_does_not_publish(self):
        result = self.update(change=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("--git-dir", str(self.remote), "branch", "--list"), "* main")
        self.assertFalse(any(r[:2] == ["pr", "create"] for r in self.requests))

    def test_obsolete_pr_closes_when_lock_matches_main(self):
        result = self.update(change=False, pr="123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(r[:3] == ["pr", "close", "123"] for r in self.requests))

    def test_concurrent_branch_writer_is_not_overwritten(self):
        result = self.update(race=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("--git-dir", str(self.remote), "rev-parse", "automation/flake-lock"), self.main)
        self.assertFalse(any(r[:2] == ["pr", "create"] for r in self.requests))


if __name__ == "__main__":
    unittest.main()
