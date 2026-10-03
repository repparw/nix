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
CI = Path(sys.argv.pop(1)).read_text()
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
                      "    print(os.environ['FIXTURE_PR'])\n"
                      "if sys.argv[1] == 'api':\n"
                      "    print(os.environ['FIXTURE_RUNS'])\n"
                      "if sys.argv[1:3] == ['pr', 'create'] and os.environ['FIXTURE_LATE_RACE'] == '1':\n"
                      "    import subprocess\n"
                      "    subprocess.run(['git', '--git-dir', os.environ['FIXTURE_REMOTE'], 'update-ref', 'refs/heads/automation/flake-lock', os.environ['FIXTURE_MAIN']], check=True)\n"
                      "if sys.argv[1:3] == ['workflow', 'run'] and os.environ['FIXTURE_DISPATCH_FAIL'] == '1':\n"
                      "    sys.exit(1)\n")
        gh.chmod(0o755)

    def git(self, *arguments, cwd=None):
        result = subprocess.run(["git", *arguments], cwd=cwd, text=True, capture_output=True, check=True)
        return result.stdout.strip()

    def update(self, change=True, pr="", race=False, runs=0, late_race=False, dispatch_fail=False):
        env = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "FIXTURE_CHANGE": str(int(change)), "FIXTURE_PR": pr,
            "FIXTURE_RACE": str(int(race)), "FIXTURE_REMOTE": str(self.remote),
            "FIXTURE_MAIN": self.main, "FIXTURE_REQUESTS": str(self.root / "requests"),
            "FIXTURE_RUNS": str(runs), "FIXTURE_LATE_RACE": str(int(late_race)),
            "FIXTURE_DISPATCH_FAIL": str(int(dispatch_fail)), "GH_REPO": "fixture/nix",
        }
        (self.root / "requests").write_text("")
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
        revision = self.git("--git-dir", str(self.remote), "rev-parse", "automation/flake-lock")
        self.assertEqual([r for r in self.requests if r[:2] == ["workflow", "run"]],
                         [["workflow", "run", "ci.yml", "--ref", "automation/flake-lock", "-f", f"expected_sha={revision}"]])
        self.assertLess(next(i for i, r in enumerate(self.requests) if r[:2] == ["pr", "create"]),
                        next(i for i, r in enumerate(self.requests) if r[:2] == ["workflow", "run"]))

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

    def reset_checkout(self):
        self.git("switch", "main", cwd=self.checkout)
        self.git("reset", "--hard", self.main, cwd=self.checkout)

    def test_unchanged_candidate_reuses_sha_and_does_not_dispatch_again(self):
        self.assertEqual(self.update().returncode, 0)
        revision = self.git("--git-dir", str(self.remote), "rev-parse", "automation/flake-lock")
        self.reset_checkout()
        result = self.update(pr="123", runs=1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("--git-dir", str(self.remote), "rev-parse", "automation/flake-lock"), revision)
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))
        query = next(r for r in self.requests if r[0] == "api")
        self.assertIn(f"head_sha={revision}", query)
        self.assertIn("branch=automation/flake-lock", query)
        self.assertIn("event=workflow_dispatch", query)

    def test_unchanged_candidate_without_ci_dispatches_existing_sha(self):
        self.assertEqual(self.update().returncode, 0)
        revision = self.git("--git-dir", str(self.remote), "rev-parse", "automation/flake-lock")
        self.reset_checkout()
        result = self.update(pr="123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("--git-dir", str(self.remote), "rev-parse", "automation/flake-lock"), revision)
        self.assertEqual([r for r in self.requests if r[:2] == ["workflow", "run"]],
                         [["workflow", "run", "ci.yml", "--ref", "automation/flake-lock", "-f", f"expected_sha={revision}"]])

    def test_branch_change_during_pr_creation_does_not_dispatch(self):
        result = self.update(late_race=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))
        self.assertIn("Lock branch changed", result.stderr)

    def test_dispatch_failure_can_retry_without_creating_duplicate_pr_or_commit(self):
        result = self.update(dispatch_fail=True)
        self.assertNotEqual(result.returncode, 0)
        revision = self.git("--git-dir", str(self.remote), "rev-parse", "automation/flake-lock")
        self.reset_checkout()
        result = self.update(pr="123", runs=1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("--git-dir", str(self.remote), "rev-parse", "automation/flake-lock"), revision)
        self.assertFalse(any(r[:2] in [["pr", "create"], ["workflow", "run"]] for r in self.requests))

    def test_no_lock_change_does_not_dispatch(self):
        self.assertEqual(self.update(change=False, pr="123").returncode, 0)
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))

    def test_ci_dispatch_guard_rejects_moved_ref(self):
        guards = [line.strip().removeprefix("run: ") for line in CI.splitlines()
                  if 'run: test "$GITHUB_SHA" = "$EXPECTED_SHA"' in line]
        checkout_count = CI.count("uses: actions/checkout@")
        self.assertGreater(checkout_count, 0)
        self.assertEqual(len(guards), checkout_count)
        for guard in guards:
            for sha, expected, success in [("a" * 40, "a" * 40, True),
                                           ("b" * 40, "a" * 40, False),
                                           ("a" * 40, "", False)]:
                result = subprocess.run(["bash", "-c", guard],
                                        env=os.environ | {"GITHUB_SHA": sha, "EXPECTED_SHA": expected})
                self.assertEqual(result.returncode == 0, success)
        self.assertEqual(CI.count("ref: ${{ github.sha }}"), checkout_count)


if __name__ == "__main__":
    unittest.main()
