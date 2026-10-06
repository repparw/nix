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
        nix.write_text(
            f"#!{shutil.which('bash')}\n"
            "if [ \"$FIXTURE_CHANGE\" = 1 ]; then printf 'new\\n' > flake.lock; fi\n"
            "if [ \"$FIXTURE_BRANCH_RACE\" = 1 ]; then "
            "git --git-dir=\"$FIXTURE_REMOTE\" update-ref refs/heads/automation/flake-lock \"$FIXTURE_MAIN\"; fi\n"
        )
        nix.chmod(0o755)

        gh = self.bin / "gh"
        gh.write_text(
            f"#!{sys.executable}\n"
            "import json, os, subprocess, sys\n"
            "from pathlib import Path\n"
            "root = Path(os.environ['FIXTURE_ROOT'])\n"
            "remote = os.environ['FIXTURE_REMOTE']\n"
            "args = sys.argv[1:]\n"
            "with Path(os.environ['FIXTURE_REQUESTS']).open('a') as log:\n"
            "    log.write(json.dumps(args) + '\\n')\n"
            "if args[:2] == ['pr', 'list']:\n"
            "    print(os.environ['FIXTURE_PR'])\n"
            "elif args[:2] == ['pr', 'create']:\n"
            "    if os.environ['FIXTURE_LATE_BRANCH_RACE'] == '1':\n"
            "        subprocess.run(['git', '--git-dir', remote, 'update-ref', "
            "'refs/heads/automation/flake-lock', os.environ['FIXTURE_MAIN']], check=True)\n"
            "    print('https://github.com/fixture/nix/pull/123')\n"
            "elif args and args[0] == 'api':\n"
            "    branch = next((a.split('=', 1)[1] for a in args if a.startswith('branch=')), '')\n"
            "    key = 'main' if branch == 'main' else 'candidate'\n"
            "    configured = os.environ[f'FIXTURE_{key.upper()}_CI']\n"
            "    marker = root / f'dispatched-{key}'\n"
            "    state = configured or ('success' if marker.exists() else '')\n"
            "    if state == 'success':\n"
            "        print('1\\tcompleted\\tsuccess')\n"
            "    elif state == 'failure':\n"
            "        print('1\\tcompleted\\tfailure')\n"
            "    elif state == 'pending':\n"
            "        print('1\\tin_progress\\t')\n"
            "elif args[:2] == ['workflow', 'run']:\n"
            "    ref = args[args.index('--ref') + 1]\n"
            "    key = 'main' if ref == 'main' else 'candidate'\n"
            "    if os.environ[f'FIXTURE_{key.upper()}_DISPATCH_FAIL'] == '1':\n"
            "        sys.exit(1)\n"
            "    (root / f'dispatched-{key}').write_text('1')\n"
        )
        gh.chmod(0o755)

        sleep = self.bin / "sleep"
        sleep.write_text(f"#!{shutil.which('bash')}\nexit 0\n")
        sleep.chmod(0o755)

        real_git = shutil.which("git")
        git = self.bin / "git"
        git.write_text(
            f"#!{shutil.which('bash')}\n"
            "set -e\n"
            "if [ \"$FIXTURE_PRE_MERGE_MAIN_RACE\" = 1 ] && [ \"$1\" = push ] "
            "&& [[ \" $* \" == *\"refs/heads/main\"* ]] "
            "&& [ ! -e \"$FIXTURE_ROOT/main-raced\" ]; then\n"
            "  current=$($REAL_GIT --git-dir=\"$FIXTURE_REMOTE\" rev-parse refs/heads/main)\n"
            "  tree=$($REAL_GIT --git-dir=\"$FIXTURE_REMOTE\" rev-parse \"$current^{tree}\")\n"
            "  race=$(printf 'racing main\\n' | "
            "GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.test "
            "GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.test "
            "$REAL_GIT --git-dir=\"$FIXTURE_REMOTE\" commit-tree \"$tree\" -p \"$current\")\n"
            "  $REAL_GIT --git-dir=\"$FIXTURE_REMOTE\" update-ref refs/heads/main \"$race\" \"$current\"\n"
            "  touch \"$FIXTURE_ROOT/main-raced\"\n"
            "fi\n"
            "exec \"$REAL_GIT\" \"$@\"\n"
        )
        git.chmod(0o755)
        self.real_git = real_git

    def git(self, *arguments, cwd=None):
        result = subprocess.run(["git", *arguments], cwd=cwd, text=True, capture_output=True, check=True)
        return result.stdout.strip()

    def update(
        self,
        *,
        change=True,
        pr="",
        candidate_ci="",
        branch_race=False,
        late_branch_race=False,
        candidate_dispatch_fail=False,
        pre_merge_main_race=False,
    ):
        env = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "FIXTURE_CHANGE": str(int(change)),
            "FIXTURE_PR": pr,
            "FIXTURE_BRANCH_RACE": str(int(branch_race)),
            "FIXTURE_LATE_BRANCH_RACE": str(int(late_branch_race)),
            "FIXTURE_CANDIDATE_CI": candidate_ci,
            "FIXTURE_MAIN_CI": "",
            "FIXTURE_CANDIDATE_DISPATCH_FAIL": str(int(candidate_dispatch_fail)),
            "FIXTURE_MAIN_DISPATCH_FAIL": "0",
            "FIXTURE_PRE_MERGE_MAIN_RACE": str(int(pre_merge_main_race)),
            "REAL_GIT": self.real_git,
            "FIXTURE_REMOTE": str(self.remote),
            "FIXTURE_MAIN": self.main,
            "FIXTURE_REQUESTS": str(self.root / "requests"),
            "FIXTURE_ROOT": str(self.root),
            "GH_REPO": "fixture/nix",
            "LOCK_UPDATE_POLL_SECONDS": "0",
            "LOCK_UPDATE_POLL_ATTEMPTS": "3",
        }
        (self.root / "requests").write_text("")
        for marker in [*self.root.glob("dispatched-*"), self.root / "main-raced"]:
            if marker.exists():
                marker.unlink()
        result = subprocess.run(
            ["bash", "-c", SCRIPT],
            cwd=self.checkout,
            env=env,
            text=True,
            capture_output=True,
        )
        self.requests = [json.loads(line) for line in (self.root / "requests").read_text().splitlines()]
        return result

    def main_sha(self):
        return self.git("--git-dir", str(self.remote), "rev-parse", "main")

    def branch_sha(self):
        return self.git("--git-dir", str(self.remote), "rev-parse", "automation/flake-lock")

    def test_creates_validates_and_fast_forwards_main_to_same_sha(self):
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("--git-dir", str(self.remote), "show", "main:flake.lock"), "new")
        self.assertEqual(self.main_sha(), self.branch_sha())

        create = next(i for i, r in enumerate(self.requests) if r[:2] == ["pr", "create"])
        candidate_dispatches = [
            (i, r) for i, r in enumerate(self.requests)
            if r[:2] == ["workflow", "run"] and r[r.index("--ref") + 1] == "automation/flake-lock"
        ]
        self.assertEqual(len(candidate_dispatches), 1)
        self.assertLess(create, candidate_dispatches[0][0])
        self.assertFalse(any(
            r[:2] == ["workflow", "run"] and r[r.index("--ref") + 1] == "main"
            for r in self.requests
        ))
        self.assertFalse(any(r[:2] == ["pr", "merge"] for r in self.requests))

        pr_list = next(r for r in self.requests if r[:2] == ["pr", "list"])
        self.assertIn("automation/flake-lock", pr_list)
        self.assertNotIn("fixture:automation/flake-lock", pr_list)

    def test_existing_pr_refreshes_without_duplicate_create(self):
        self.git("push", "origin", "HEAD:refs/heads/automation/flake-lock", cwd=self.checkout)
        result = self.update(pr="123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(r[:2] == ["pr", "create"] for r in self.requests))
        self.assertFalse(any(r[:2] == ["pr", "merge"] for r in self.requests))
        self.assertEqual(self.git("--git-dir", str(self.remote), "show", "main:flake.lock"), "new")
        self.assertEqual(self.main_sha(), self.branch_sha())

    def test_no_change_closes_obsolete_pr_without_merge(self):
        result = self.update(change=False, pr="123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(r[:3] == ["pr", "close", "123"] for r in self.requests))
        self.assertEqual(self.main_sha(), self.main)

    def test_candidate_failure_does_not_merge(self):
        result = self.update(candidate_ci="failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(r[:2] == ["pr", "merge"] for r in self.requests))
        self.assertEqual(self.main_sha(), self.main)

    def test_existing_successful_candidate_ci_is_reused(self):
        result = self.update(candidate_ci="success")
        self.assertEqual(result.returncode, 0, result.stderr)
        candidate_dispatches = [
            r for r in self.requests
            if r[:2] == ["workflow", "run"] and r[r.index("--ref") + 1] == "automation/flake-lock"
        ]
        self.assertEqual(candidate_dispatches, [])
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))
        self.assertEqual(self.main_sha(), self.branch_sha())

    def test_branch_change_during_pr_creation_does_not_merge(self):
        result = self.update(late_branch_race=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Lock branch changed", result.stderr)
        self.assertEqual(self.main_sha(), self.main)

    def test_candidate_dispatch_failure_does_not_merge(self):
        result = self.update(candidate_dispatch_fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.main_sha(), self.main)

    def test_main_race_after_final_check_rejects_atomic_merge(self):
        result = self.update(pre_merge_main_race=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / "main-raced").exists())
        self.assertIn("main changed before the atomic lock fast-forward", result.stderr)

        # The racing main commit wins, but it still has the old lock tree. The
        # validated lock candidate must not be reachable from main.
        raced_main = self.main_sha()
        self.assertNotEqual(raced_main, self.main)
        self.assertEqual(self.git("--git-dir", str(self.remote), "show", "main:flake.lock"), "old")
        candidate = self.branch_sha()
        ancestry = subprocess.run(
            ["git", "--git-dir", str(self.remote), "merge-base", "--is-ancestor", candidate, raced_main]
        )
        self.assertNotEqual(ancestry.returncode, 0)
        self.assertFalse(any(
            r[:2] == ["workflow", "run"] and r[r.index("--ref") + 1] == "main"
            for r in self.requests
        ))

    def test_no_lock_change_does_not_dispatch(self):
        result = self.update(change=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))
        self.assertEqual(self.main_sha(), self.main)

    def test_ci_dispatch_guard_rejects_moved_ref(self):
        guards = [
            line.strip().removeprefix("run: ")
            for line in CI.splitlines()
            if 'run: test "$GITHUB_SHA" = "$EXPECTED_SHA"' in line
        ]
        checkout_count = CI.count("uses: actions/checkout@")
        self.assertGreater(checkout_count, 0)
        self.assertEqual(len(guards), checkout_count)
        for guard in guards:
            for sha, expected, success in [
                ("a" * 40, "a" * 40, True),
                ("b" * 40, "a" * 40, False),
                ("a" * 40, "", False),
            ]:
                result = subprocess.run(
                    ["bash", "-c", guard],
                    env=os.environ | {"GITHUB_SHA": sha, "EXPECTED_SHA": expected},
                )
                self.assertEqual(result.returncode == 0, success)
        self.assertEqual(CI.count("ref: ${{ github.sha }}"), checkout_count)
        self.assertIn("paths-ignore:", CI)
        self.assertIn("- flake.lock", CI)


if __name__ == "__main__":
    unittest.main()
