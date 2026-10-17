"""Exercise the lock workflow's shell step against a local Git remote."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

WORKFLOW_PATH = Path(sys.argv.pop(1))
REPO = WORKFLOW_PATH.resolve().parents[2]
WORKFLOW = WORKFLOW_PATH.read_text()
CI = Path(sys.argv.pop(1)).read_text()
VALIDATION = Path(sys.argv.pop(1)).read_text() if len(sys.argv) > 1 else CI
UPDATE = WORKFLOW.split("        run: |\n", 1)[1]
SCRIPT = "\n".join(line.removeprefix("          ") for line in UPDATE.splitlines())


def lock_fixture(revision):
    return json.dumps({
        "root": "root",
        "nodes": {
            "root": {"inputs": {"nixpkgs": "nixpkgs_3", "home-manager": "home-manager_2"}},
            "nixpkgs_3": {"locked": {"rev": revision}},
            "home-manager_2": {"locked": {"rev": "home-manager"}},
        },
    })


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
        # The real lock updater invokes this planner from the checkout, not
        # the test runner's source tree. Carry the production implementation
        # and exact fixture into every disposable repository.
        for path in (".github/scripts/upstream-plan.py", ".github/scripts/upstream-readiness.py",
                     ".github/upstream/watchers.json"):
            dst = self.checkout / path
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(REPO / path, dst)
            # Nix-store source fixtures are read-only; the disposable checkout
            # must be writable for the fixture registry and atomic cleanup.
            dst.chmod(0o644)
        module = self.checkout / "modules/_services/authelia.nix"
        module.parent.mkdir(parents=True, exist_ok=True)
        # Main has already retired Authelia; fixture must reproduce that
        # otherwise a ready qBittorrent cleanup would also select Authelia.
        module.write_text("services.authelia.instances.main = {\n  package = pkgs.authelia;\n};\n")
        # A fixture registry: one apply-coupled watcher whose workaround file,
        # cleanup recipe, and readiness endpoints the fake gh can answer.
        registry = {
            "authelia-pnpm-hash": {"mode": "atomic", "input": "nixpkgs",
                                   "fix_commit": "fix", "cleanup": "authelia-override"},
            "qbittorrent": {"mode": "post-lock", "input": "nixpkgs",
                                "cleanup": "fixture-cleanup.patch", "coupling": "apply"},
        }
        (self.checkout / ".github/upstream/watchers.json").write_text(json.dumps(registry, indent=2))
        # The fixture id must be a real readiness detector, and the file must
        # carry that detector's workaround marker (or inspect reports completed).
        workaround = self.checkout / "modules/aspects/services/arr.nix"
        workaround.parent.mkdir(parents=True, exist_ok=True)
        workaround.write_text("keep\nqbittorrent-nox.overrideAttrs\nworkaround\n")
        recipe = self.checkout / ".github/upstream/cleanup/fixture-cleanup.patch"
        recipe.parent.mkdir(parents=True, exist_ok=True)
        recipe.write_text(
            "diff --git a/modules/aspects/services/arr.nix b/modules/aspects/services/arr.nix\n"
            "--- a/modules/aspects/services/arr.nix\n"
            "+++ b/modules/aspects/services/arr.nix\n"
            "@@ -1,3 +1 @@\n keep\n-qbittorrent-nox.overrideAttrs\n-workaround\n")
        # Nix-store source fixtures are read-only; a real Git checkout is writable.
        # Exercise the atomic cleanup against checkout-like permissions.
        module.chmod(0o644)
        (self.checkout / "flake.lock").write_text(lock_fixture("old"))
        self.git("add", ".", cwd=self.checkout)
        self.git("commit", "-m", "fixture", cwd=self.checkout)
        self.git("push", "origin", "main", cwd=self.checkout)
        self.main = self.git("rev-parse", "HEAD", cwd=self.checkout)
        self.bin = self.root / "bin"
        self.bin.mkdir()

        (self.root / "next.lock").write_text(lock_fixture("new"))
        nix = self.bin / "nix"
        nix.write_text(
            f"#!{shutil.which('bash')}\n"
            "if [ \"$FIXTURE_CHANGE\" = 1 ]; then cp \"$FIXTURE_ROOT/next.lock\" flake.lock; fi\n"
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
            "    atomic = 'automation/atomic-cleanup' in args\n"
            "    if '--state' in args and args[args.index('--state') + 1] == 'merged':\n"
            "        tip = subprocess.check_output(['git', '--git-dir', remote, 'rev-parse', 'automation/atomic-cleanup'], text=True).strip()\n"
            "        print(tip if (root/'atomic-merged').exists() else '')\n"
            "    else:\n"
            "        print('123' if (root/'atomic-pr').exists() else '' if atomic else os.environ['FIXTURE_PR'])\n"
            "elif args[:2] == ['pr', 'create']:\n"
            "    if 'automation/atomic-cleanup' in args:\n"
            "        (root/'atomic-pr').write_text('123')\n"
            "    elif os.environ['FIXTURE_LATE_BRANCH_RACE'] == '1':\n"
            "        subprocess.run(['git', '--git-dir', remote, 'update-ref', "
            "'refs/heads/automation/flake-lock', os.environ['FIXTURE_MAIN']], check=True)\n"
            "    print('https://github.com/fixture/nix/pull/123')\n"
            "elif args[:2] == ['pr', 'view']:\n"
            "    if 'autoMergeRequest' in args:\n"
            "        print('true' if (root/'auto-merged').exists() else 'false')\n"
            "    else:\n"
            "        sha = subprocess.check_output(['git','--git-dir',remote,'rev-parse','automation/atomic-cleanup'], text=True).strip()\n"
            "        print(sha)\n"
            "elif args[:2] == ['pr', 'merge']:\n"
            "    (root/'auto-merged').write_text('1')\n"
            "elif args and args[0] == 'api':\n"
            "    endpoint = next(arg for arg in args if arg.startswith('repos/'))\n"
            "    if '/compare/' in endpoint:\n"
            "        fix = endpoint.split('/compare/')[1].split('...')[0]\n"
            "        ready = os.environ['FIXTURE_ATOMIC_READY'] == '1'\n"
            "        print(json.dumps({'status': 'ahead' if ready else 'behind', 'merge_base_commit': {'sha': fix}}))\n"
            "        sys.exit(0)\n"
            "    if endpoint.endswith('/commits/nixos-unstable'):\n"
            "        print(json.dumps({'sha':'channel'})); sys.exit(0)\n"
            "    if '/pulls/24055' in endpoint:\n"
            "        print(json.dumps({'merged': True, 'merge_commit_sha': 'fix'})); sys.exit(0)\n"
            "    if '/contents/' in endpoint:\n"
            "        import base64\n"
            "        body = b'rev = \"fix\";'\n"
            "        print(json.dumps({'content': base64.b64encode(body).decode()})); sys.exit(0)\n"
            "    if 'actions/runs/21/jobs' in endpoint or 'actions/runs/22/jobs' in endpoint:\n"
            "        print('1'); sys.exit(0)\n"
            "    if 'actions/runs/21' in endpoint or 'actions/runs/22' in endpoint:\n"
            "        print('success' if '.conclusion' in args else 'completed'); sys.exit(0)\n"
            "    if 'branch=automation/atomic-cleanup' in args:\n"
            "        if 'pr-title.yml/runs' in endpoint:\n"
            "            print('1' if (root/'dispatched-atomic-title').exists() else '0')\n"
            "        elif 'ci.yml/runs' in endpoint:\n"
            "            runs = []\n"
            "            if (root/'dispatched-atomic').exists():\n"
            "                runs.append({'id': 21, 'display_title': (root/'atomic-manifest').read_text()})\n"
            "            if (root/'wrong-atomic-manifest').exists():\n"
            "                runs.append({'id': 22, 'display_title': (root/'wrong-atomic-manifest').read_text()})\n"
            "            print(json.dumps({'workflow_runs': runs}))\n"
            "        sys.exit(0)\n"
            "    sha = subprocess.check_output(['git', '--git-dir', remote, 'rev-parse', 'automation/flake-lock'], text=True).strip()\n"
            "    if '/pulls/' in endpoint:\n"
            "        print(json.dumps({'state': 'open', 'head': {'repo': {'full_name': 'fixture/nix'}, 'ref': 'automation/flake-lock', 'sha': 'wrong' if os.environ['FIXTURE_WRONG_PR_HEAD'] == '1' else sha}, 'base': {'ref': 'main'}}))\n"
            "        sys.exit(0)\n"
            "    if endpoint.endswith('/approve'):\n"
            "        if os.environ['FIXTURE_APPROVAL_FAIL'] == '1': sys.exit(1)\n"
            "        (root / ('approved-' + endpoint.split('/')[-2])).write_text('1')\n"
            "        sys.exit(0)\n"
            "    if 'event=pull_request' in args:\n"
            "        workflow = 'pr-title.yml' if 'pr-title.yml/runs' in endpoint else 'ci.yml'\n"
            "        run = 12 if workflow == 'pr-title.yml' else 11\n"
            "        conclusion = os.environ['FIXTURE_PR_CI'] if (root / f'approved-{run}').exists() else 'action_required'\n"
            "        print(json.dumps({'id': run, 'status': 'completed', 'conclusion': conclusion, 'head_sha': sha, 'head_branch': 'automation/flake-lock', 'event': 'pull_request', 'path': '.github/workflows/' + ('other.yml' if os.environ['FIXTURE_WRONG_RUN_PATH'] == '1' else workflow)}))\n"
            "        sys.exit(0)\n"
            "    if any('pr-title.yml/runs' in arg for arg in args):\n"
            "        if (root / 'dispatched-title').exists(): print('2')\n"
            "        sys.exit(0)\n"
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
            "    key = ('atomic-title' if args[2] == 'pr-title.yml' else 'atomic') if ref == 'automation/atomic-cleanup' else ('title' if args[2] == 'pr-title.yml' else ('main' if ref == 'main' else 'candidate'))\n"
            "    if os.environ[f'FIXTURE_{key.upper().replace(chr(45), chr(95))}_DISPATCH_FAIL'] == '1':\n"
            "        sys.exit(1)\n"
            "    (root / f'dispatched-{key}').write_text('1')\n"
            "    if key == 'atomic':\n"
            "        items = [a.split('=', 1) for a in args if '=' in a]\n"
            "        params = dict(items)\n"
            "        (root/'atomic-manifest').write_text('validate sha=' + params['expected_sha'] +\n"
            "            ' watchers=' + params.get('upstream_watcher', 'none') +\n"
            "            ' arm=' + params.get('build_arm_authelia', 'false'))\n"
            "elif args[:2] == ['run', 'watch']:\n"
            "    sys.exit(1 if os.environ['FIXTURE_TITLE_CI'] == 'failure' else 0)\n"
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
        event="workflow_dispatch",
        pr="",
        candidate_ci="",
        title_ci="success",
        branch_race=False,
        late_branch_race=False,
        candidate_dispatch_fail=False,
        pre_merge_main_race=False,
        approval_fail=False,
        wrong_pr_head=False,
        wrong_run_path=False,
        pr_ci="success",
        atomic_ready=False,
        atomic_dispatch_fail=False,
    ):
        env = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "FIXTURE_CHANGE": str(int(change)),
            "FIXTURE_PR": pr,
            "FIXTURE_BRANCH_RACE": str(int(branch_race)),
            "FIXTURE_LATE_BRANCH_RACE": str(int(late_branch_race)),
            "FIXTURE_CANDIDATE_CI": candidate_ci,
            "FIXTURE_TITLE_CI": title_ci,
            "FIXTURE_TITLE_DISPATCH_FAIL": "0",
            "FIXTURE_MAIN_CI": "",
            "FIXTURE_CANDIDATE_DISPATCH_FAIL": str(int(candidate_dispatch_fail)),
            "FIXTURE_MAIN_DISPATCH_FAIL": "0",
            "FIXTURE_ATOMIC_DISPATCH_FAIL": str(int(atomic_dispatch_fail)),
            "FIXTURE_PRE_MERGE_MAIN_RACE": str(int(pre_merge_main_race)),
            "FIXTURE_APPROVAL_FAIL": str(int(approval_fail)),
            "FIXTURE_WRONG_PR_HEAD": str(int(wrong_pr_head)),
            "FIXTURE_WRONG_RUN_PATH": str(int(wrong_run_path)),
            "FIXTURE_PR_CI": pr_ci,
            "FIXTURE_ATOMIC_READY": str(int(atomic_ready)),
            "FIXTURE_ATOMIC_TITLE_DISPATCH_FAIL": "0",
            "REAL_GIT": self.real_git,
            "FIXTURE_REMOTE": str(self.remote),
            "FIXTURE_MAIN": self.main,
            "FIXTURE_REQUESTS": str(self.root / "requests"),
            "FIXTURE_ROOT": str(self.root),
            "GH_REPO": "fixture/nix",
            "GITHUB_EVENT_NAME": event,
            "LOCK_UPDATE_POLL_SECONDS": "0",
            "LOCK_UPDATE_POLL_ATTEMPTS": "3",
        }
        (self.root / "requests").write_text("")
        for marker in [*self.root.glob("dispatched-*"), *self.root.glob("approved-*"), self.root / "main-raced"]:
            if marker.name.startswith("dispatched-atomic"):
                continue
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
        self.assertEqual(self.git("--git-dir", str(self.remote), "show", "main:flake.lock"), lock_fixture("new"))
        self.assertEqual(self.main_sha(), self.branch_sha())

        create = next(i for i, r in enumerate(self.requests) if r[:2] == ["pr", "create"])
        candidate_dispatches = [
            (i, r) for i, r in enumerate(self.requests)
            if r[:2] == ["workflow", "run"] and r[r.index("--ref") + 1] == "automation/flake-lock"
        ]
        self.assertEqual(len(candidate_dispatches), 2)
        self.assertEqual({request[2] for _, request in candidate_dispatches}, {"ci.yml", "pr-title.yml"})
        self.assertLess(create, candidate_dispatches[0][0])
        self.assertFalse(any(
            r[:2] == ["workflow", "run"] and r[r.index("--ref") + 1] == "main"
            for r in self.requests
        ))
        self.assertFalse(any(r[:2] == ["pr", "merge"] for r in self.requests))

        pr_list = next(r for r in self.requests if r[:2] == ["pr", "list"] and "automation/flake-lock" in r)
        self.assertIn("automation/flake-lock", pr_list)
        self.assertNotIn("fixture:automation/flake-lock", pr_list)

    def test_existing_pr_refreshes_without_duplicate_create(self):
        self.git("push", "origin", "HEAD:refs/heads/automation/flake-lock", cwd=self.checkout)
        result = self.update(pr="123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(r[:2] == ["pr", "create"] for r in self.requests))
        self.assertFalse(any(r[:2] == ["pr", "merge"] for r in self.requests))
        self.assertEqual(self.git("--git-dir", str(self.remote), "show", "main:flake.lock"), lock_fixture("new"))
        self.assertEqual(self.main_sha(), self.branch_sha())

    def test_scheduled_secondary_change_closes_pr_without_publishing(self):
        updated = json.loads(lock_fixture("old"))
        updated["nodes"]["secondary"] = {"locked": {"rev": "new"}}
        (self.root / "next.lock").write_text(json.dumps(updated))
        result = self.update(event="schedule", pr="123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([r[:3] for r in self.requests], [["pr", "list", "--head"], ["pr", "list", "--head"], ["pr", "close", "123"]])
        self.assertEqual(self.main_sha(), self.main)

    def test_scheduled_primary_change_validates_and_publishes(self):
        result = self.update(event="schedule")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.main_sha(), self.branch_sha())
        self.assertNotEqual(self.main_sha(), self.main)

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
            if r[:3] == ["workflow", "run", "ci.yml"] and r[r.index("--ref") + 1] == "automation/flake-lock"
        ]
        self.assertEqual(candidate_dispatches, [])
        title_dispatches = [r for r in self.requests if r[:3] == ["workflow", "run", "pr-title.yml"]]
        self.assertEqual(len(title_dispatches), 1)
        self.assertIn("pull_request_number=123", title_dispatches[0])
        self.assertIn("expected_sha=" + self.branch_sha(), title_dispatches[0])
        self.assertEqual(self.main_sha(), self.branch_sha())

    def test_title_failure_does_not_publish_validated_lock(self):
        result = self.update(title_ci="failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.main_sha(), self.main)

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
        self.assertIn("Atomic lock fast-forward was rejected", result.stderr)

        # The racing main commit wins, but it still has the old lock tree. The
        # validated lock candidate must not be reachable from main.
        raced_main = self.main_sha()
        self.assertNotEqual(raced_main, self.main)
        self.assertEqual(self.git("--git-dir", str(self.remote), "show", "main:flake.lock"), lock_fixture("old"))
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

    def test_approves_both_required_pr_runs_before_publishing(self):
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        approvals = [r for r in self.requests if r[0] == "api" and any(a.endswith('/approve') for a in r)]
        self.assertEqual(len(approvals), 2)
        self.assertEqual(self.main_sha(), self.branch_sha())

    def test_approval_failure_cannot_publish_despite_successful_dispatches(self):
        result = self.update(approval_fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.main_sha(), self.main)

    def test_normal_pr_failure_cannot_publish_despite_successful_dispatches(self):
        result = self.update(pr_ci="failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.main_sha(), self.main)

    def test_stale_pr_cannot_be_approved(self):
        result = self.update(wrong_pr_head=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.main_sha(), self.main)
        self.assertFalse(any(r[0] == "api" and any(a.endswith('/approve') for a in r) for r in self.requests))

    def test_unexpected_workflow_cannot_be_approved(self):
        result = self.update(wrong_run_path=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.main_sha(), self.main)
        self.assertFalse(any(r[0] == "api" and any(a.endswith('/approve') for a in r) for r in self.requests))

    def test_atomic_candidate_carries_cleanup_and_arms_automerge(self):
        result = self.update(atomic_ready=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.main_sha(), self.main, "GitHub merges the armed candidate, not this workflow")
        atomic = self.git("--git-dir", str(self.remote), "rev-parse", "automation/atomic-cleanup")
        self.assertEqual(self.git("--git-dir", str(self.remote), "show", "automation/atomic-cleanup:flake.lock"), lock_fixture("new"))
        arr = self.git("--git-dir", str(self.remote), "show", "automation/atomic-cleanup:modules/aspects/services/arr.nix")
        self.assertEqual(arr, "keep")
        self.assertEqual(
            {r[2] for r in self.requests if r[:2] == ["workflow", "run"]
             and r[r.index("--ref") + 1] == "automation/atomic-cleanup"},
            {"ci.yml", "pr-title.yml"},
        )
        ci_dispatch = next(r for r in self.requests if r[:3] == ["workflow", "run", "ci.yml"]
                           and r[r.index("--ref") + 1] == "automation/atomic-cleanup")
        self.assertIn("upstream_watcher=qbittorrent", ci_dispatch)
        self.assertFalse(any(r[0] == "api" and any(a.endswith("/approve") for a in r) for r in self.requests))
        self.assertTrue(any(r[:2] == ["pr", "merge"] and "--auto" in r for r in self.requests),
                        "the atomic candidate must be merge-automated")

    def test_interrupted_atomic_dispatch_retries_without_rewriting_branch(self):
        first = self.update(atomic_ready=True, atomic_dispatch_fail=True)
        self.assertNotEqual(first.returncode, 0)
        original = self.git("--git-dir", str(self.remote), "rev-parse", "automation/atomic-cleanup")
        self.git("switch", "main", cwd=self.checkout)
        second = self.update(change=False)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.main_sha(), self.main)
        self.assertEqual(self.git("--git-dir", str(self.remote), "rev-parse", "automation/atomic-cleanup"), original)
        self.assertEqual([r[2] for r in self.requests if r[:2] == ["workflow", "run"]], ["ci.yml"])
        self.assertIn("upstream_watcher=qbittorrent",
                      next(r for r in self.requests if r[:3] == ["workflow", "run", "ci.yml"]))

    def test_recovery_fetches_candidate_in_fresh_checkout(self):
        first = self.update(atomic_ready=True, atomic_dispatch_fail=True)
        self.assertNotEqual(first.returncode, 0)
        fresh = self.root / "fresh"
        self.git("clone", "--single-branch", "--branch", "main",
                 str(self.remote), str(fresh))
        self.git("config", "user.name", "fixture", cwd=fresh)
        self.git("config", "user.email", "fixture@example.test", cwd=fresh)
        # Unlike the first checkout this one has never fetched the atomic tip.
        self.checkout = fresh
        second = self.update(change=False)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertTrue(any(r[:3] == ["workflow", "run", "ci.yml"]
                            for r in self.requests))
        self.assertTrue(any(r[:2] == ["pr", "merge"] for r in self.requests))

    def test_merged_atomic_branch_is_safely_retired(self):
        first = self.update(atomic_ready=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        tip = self.git("--git-dir", str(self.remote), "rev-parse",
                       "automation/atomic-cleanup")
        # Simulate GitHub merging the candidate without deleting its branch.
        self.git("--git-dir", str(self.remote), "update-ref",
                 "refs/heads/main", tip, self.main)
        (self.root / "atomic-merged").write_text("1")
        (self.root / "atomic-pr").unlink()
        self.git("switch", "main", cwd=self.checkout)
        self.git("pull", "--ff-only", cwd=self.checkout)
        self.main = tip
        second = self.update(change=False)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertFalse(subprocess.run(
            ["git", "--git-dir", str(self.remote), "show-ref", "--verify",
             "refs/heads/automation/atomic-cleanup"],
            capture_output=True).returncode == 0)

    def test_unmerged_atomic_branch_must_not_be_deleted(self):
        first = self.update(atomic_ready=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        (self.root / "atomic-pr").unlink()
        self.git("switch", "main", cwd=self.checkout)
        second = self.update(change=False)
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("Unowned atomic branch", second.stderr)
        self.assertTrue(self.git("--git-dir", str(self.remote), "rev-parse",
                                 "automation/atomic-cleanup"))

    def test_authelia_candidate_is_manual_and_runs_native_arm(self):
        module = self.checkout / "modules/_services/authelia.nix"
        shutil.copy(REPO / ".github/upstream/fixtures/authelia-before.nix.txt", module)
        module.chmod(0o644)
        self.git("add", ".", cwd=self.checkout)
        self.git("commit", "-m", "restore Authelia fixture", cwd=self.checkout)
        self.git("push", "origin", "main", cwd=self.checkout)
        self.main = self.git("rev-parse", "HEAD", cwd=self.checkout)
        result = self.update(atomic_ready=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        dispatch = next(r for r in self.requests if r[:3] == ["workflow", "run", "ci.yml"]
                        and r[r.index("--ref") + 1] == "automation/atomic-cleanup")
        self.assertIn("build_arm_authelia=true", dispatch)
        self.assertIn("upstream_watcher=qbittorrent", dispatch)
        self.assertFalse(any(r[:2] == ["pr", "merge"] for r in self.requests))
        text = self.git("--git-dir", str(self.remote), "show",
                        "automation/atomic-cleanup:modules/_services/authelia.nix")
        self.assertNotIn("autheliaPackage", text)

    def test_recovery_rejects_successful_ci_for_wrong_watcher_manifest(self):
        first = self.update(atomic_ready=True, atomic_dispatch_fail=True)
        self.assertNotEqual(first.returncode, 0)
        tip = self.git("--git-dir", str(self.remote), "rev-parse",
                       "automation/atomic-cleanup")
        # A successful manual workflow dispatch at the right SHA can validate
        # a different watcher. It must not count for this candidate.
        (self.root / "wrong-atomic-manifest").write_text(
            f"validate sha={tip} watchers=moonshine-pr227 arm=false")
        self.git("switch", "main", cwd=self.checkout)
        second = self.update(change=False)
        self.assertEqual(second.returncode, 0, second.stderr)
        dispatched = [r for r in self.requests if r[:3] ==
                      ["workflow", "run", "ci.yml"]]
        self.assertEqual(len(dispatched), 1)
        self.assertIn("upstream_watcher=qbittorrent", dispatched[0])
        self.assertFalse(any("actions/runs/22/jobs" in str(r) for r in self.requests))

    def test_recovery_rejects_successful_ci_for_wrong_arm_flag(self):
        first = self.update(atomic_ready=True, atomic_dispatch_fail=True)
        self.assertNotEqual(first.returncode, 0)
        tip = self.git("--git-dir", str(self.remote), "rev-parse",
                       "automation/atomic-cleanup")
        (self.root / "wrong-atomic-manifest").write_text(
            f"validate sha={tip} watchers=qbittorrent arm=true")
        self.git("switch", "main", cwd=self.checkout)
        second = self.update(change=False)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertTrue(any(r[:3] == ["workflow", "run", "ci.yml"]
                            for r in self.requests))

    def test_ci_run_name_includes_exact_dispatch_inputs(self):
        self.assertIn("run-name: >-", CI)
        self.assertIn("inputs.expected_sha", CI)
        self.assertIn("inputs.upstream_watcher", CI)
        self.assertIn("inputs.build_arm_authelia", CI)

    def test_lock_publisher_shell_is_parseable(self):
        # Workflow YAML checks alone do not parse the embedded bash script.
        result = subprocess.run(["bash", "-n"], input=SCRIPT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_ci_dispatch_guard_rejects_moved_ref(self):
        guards = [
            line.strip().removeprefix("run: ")
            for line in VALIDATION.splitlines()
            if 'run: test "$GITHUB_SHA" = "$EXPECTED_SHA"' in line
        ]
        checkout_count = VALIDATION.count("uses: actions/checkout@")
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
        self.assertEqual(VALIDATION.count("ref: ${{ github.sha }}"), checkout_count)
        self.assertIn("  pull_request:", CI)
        self.assertNotIn("paths-ignore:", CI)


if __name__ == "__main__":
    unittest.main()
