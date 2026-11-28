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
        for path in (".github/scripts/upstream-plan.py", ".github/scripts/upstream-readiness.py",
                     ".github/scripts/upstream_cleanup.py",
                     "modules/aspects/upstream/watchers.json"):
            dst = self.checkout / path
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(REPO / path, dst)
            dst.chmod(0o644)

        registry = {

            "qbittorrent": {"mode": "post-lock", "input": "nixpkgs",
                                "coupling": "apply",
                                "probe": "nixosConfigurations.alpha.config.containers.qbittorrent.config.services.qbittorrent.package"},
        }
        (self.checkout / "modules/aspects/upstream/watchers.json").write_text(json.dumps(registry, indent=2))
        workaround = self.checkout / "modules/aspects/upstream/qbittorrent.nix"
        workaround.parent.mkdir(parents=True, exist_ok=True)
        workaround.write_text("keep\nqbittorrent-nox.overrideAttrs\nworkaround\n")
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
            "if args[:2] != ['auth', 'setup-git']:\n"
            "    with Path(os.environ['FIXTURE_REQUESTS']).open('a') as log:\n"
            "        log.write(json.dumps(args) + '\\n')\n"
            "if args[:2] == ['pr', 'list']:\n"
            "    atomic = 'automation/atomic-cleanup' in args\n"
            "    if '--state' in args and args[args.index('--state') + 1] == 'merged':\n"
            "        tip = subprocess.check_output(['git', '--git-dir', remote, 'rev-parse', 'automation/atomic-cleanup'], text=True).strip()\n"
            "        print(tip if (root/'atomic-merged').exists() else '')\n"
            "    else:\n"
            "        print('124' if (root/'atomic-pr').exists() else '' if atomic else os.environ['FIXTURE_PR'])\n"
            "elif args[:2] == ['pr', 'create']:\n"
            "    if 'automation/atomic-cleanup' in args:\n"
            "        (root/'atomic-pr').write_text('124')\n"
            "        if '--body' in args:\n"
            "            (root/'atomic-body').write_text(args[args.index('--body') + 1])\n"
            "    elif os.environ['FIXTURE_LATE_BRANCH_RACE'] == '1':\n"
            "        subprocess.run(['git', '--git-dir', remote, 'update-ref', "
            "'refs/heads/automation/flake-lock', os.environ['FIXTURE_MAIN']], check=True)\n"
            "    print('https://github.com/fixture/nix/pull/124' if 'automation/atomic-cleanup' in args else 'https://github.com/fixture/nix/pull/123')\n"
            "elif args[:2] == ['pr', 'edit']:\n"
            "    if '--body' in args:\n"
            "        (root/'atomic-body').write_text(args[args.index('--body') + 1])\n"
            "elif args[:2] == ['pr', 'view']:\n"
            "    if 'autoMergeRequest' in args:\n"
            "        print('true' if (root/'auto-merged').exists() else 'false')\n"
            "    elif 'body' in args:\n"
            "        body = root/'atomic-body'\n"
            "        print(body.read_text() if body.exists() else '')\n"
            "    else:\n"
            "        sha = subprocess.check_output(['git','--git-dir',remote,'rev-parse','automation/atomic-cleanup'], text=True).strip()\n"
            "        print('wrong' if os.environ['FIXTURE_ATOMIC_WRONG_HEAD'] == '1' else sha)\n"
            "elif args[:2] == ['pr', 'merge']:\n"
            "    if '--disable-auto' in args:\n"
            "        if (root/'disable-fails').exists(): sys.exit(1)\n"
            "        (root/'auto-merged').unlink(missing_ok=True)\n"
            "    else:\n"
            "        if (root/'replace-before-merge').exists():\n"
            "            subprocess.run(['git', '--git-dir', remote, 'update-ref', 'refs/heads/automation/atomic-cleanup', os.environ['FIXTURE_MAIN']], check=True)\n"
            "        tip = subprocess.check_output(['git', '--git-dir', remote, 'rev-parse', 'automation/atomic-cleanup'], text=True).strip()\n"
            "        if '--match-head-commit' not in args or args[args.index('--match-head-commit') + 1] != tip: sys.exit(1)\n"
            "        if '--auto' in args: sys.exit(1)\n"
            "        (root/'auto-merged').write_text(tip)\n"
            "elif args and args[0] == 'api':\n"
            "    endpoint = next(arg for arg in args if arg.startswith('repos/'))\n"
            "    if '/compare/' in endpoint:\n"
            "        parts = endpoint.split('/compare/')[1].split('...')\n"
            "        fix = parts[0]\n"
            "        revision = parts[1].split('?')[0] if len(parts) > 1 else ''\n"
            "        pinned = os.environ['FIXTURE_ATOMIC_READY'] == '1' or (root/'atomic-pr').exists()\n"
            "        ready = pinned and (revision == fix or revision in ('new', 'channel'))\n"
            "        print(json.dumps({'status': 'ahead' if ready else 'behind', 'merge_base_commit': {'sha': fix}}))\n"
            "        sys.exit(0)\n"
            "    if endpoint.endswith('/commits/nixos-unstable'):\n"
            "        print(json.dumps({'sha':'channel'})); sys.exit(0)\n"
            "    if '/pulls/24055' in endpoint:\n"
            "        print(json.dumps({'merged': True, 'merge_commit_sha': 'fix'})); sys.exit(0)\n"
            "    if endpoint == 'repos/qbittorrent/qBittorrent/pulls/24828':\n"
            "        print(json.dumps({'merged': False})); sys.exit(0)\n"
            "    if '/contents/' in endpoint:\n"
            "        import base64\n"
            "        ref = endpoint.split('ref=')[1].split('&')[0] if 'ref=' in endpoint else ''\n"
            "        pinned = os.environ['FIXTURE_ATOMIC_READY'] == '1' or (root/'atomic-pr').exists()\n"
            "        body = b'rev = \"fix\";' if (pinned and ref in ('new', 'channel')) else b'rev = \"other\";'\n"
            "        print(json.dumps({'content': base64.b64encode(body).decode()})); sys.exit(0)\n"
            "    if 'branch=automation/atomic-cleanup' in args:\n"
            "        if 'event=pull_request' in args:\n"
            "            workflow = 'pr-title.yml' if 'pr-title.yml/runs' in endpoint else 'ci.yml'\n"
            "            run = 32 if workflow == 'pr-title.yml' else 31\n"
            "            head_sha = next((a.split('=', 1)[1] for a in args if a.startswith('head_sha=')), '')\n"
            "            conclusion = os.environ['FIXTURE_TITLE_CI'] if workflow == 'pr-title.yml' else os.environ['FIXTURE_PR_CI']\n"
            "            if conclusion == 'missing': print(''); sys.exit(0)\n"
            "            status = 'in_progress' if conclusion == 'pending' else 'completed'\n"
            "            print(json.dumps({'id': run, 'status': status, 'conclusion': None if conclusion == 'pending' else conclusion, 'head_sha': head_sha, 'head_branch': 'automation/atomic-cleanup', 'event': 'pull_request', 'path': '.github/workflows/' + workflow}))\n"
            "        sys.exit(0)\n"
            "    sha = None\n"
            "    try:\n"
            "        sha = subprocess.check_output(['git', '--git-dir', remote, 'rev-parse', 'automation/flake-lock'], text=True).strip()\n"
            "    except subprocess.CalledProcessError:\n"
            "        pass\n"
            "    if '/pulls/' in endpoint:\n"
            "        number = endpoint.rsplit('/', 1)[1]\n"
            "        if number == '124':\n"
            "            try:\n"
            "                tip = subprocess.check_output(['git', '--git-dir', remote, 'rev-parse', 'automation/atomic-cleanup'], text=True).strip()\n"
            "            except subprocess.CalledProcessError:\n"
            "                print(json.dumps({'state': 'closed'})); sys.exit(0)\n"
            "            head = 'wrong' if os.environ['FIXTURE_ATOMIC_WRONG_HEAD'] == '1' else tip\n"
            "            print(json.dumps({'state': 'open', 'head': {'repo': {'full_name': 'fixture/nix'}, 'ref': 'automation/atomic-cleanup', 'sha': head}, 'base': {'ref': 'main'}}))\n"
            "            sys.exit(0)\n"
            "        print(json.dumps({'state': 'open', 'head': {'repo': {'full_name': 'fixture/nix'}, 'ref': 'automation/flake-lock', 'sha': 'wrong' if os.environ['FIXTURE_WRONG_PR_HEAD'] == '1' else sha}, 'base': {'ref': 'main'}}))\n"
            "        sys.exit(0)\n"

            "    if 'event=pull_request' in args:\n"
            "        workflow = 'pr-title.yml' if 'pr-title.yml/runs' in endpoint else 'ci.yml'\n"
            "        run = 12 if workflow == 'pr-title.yml' else 11\n"
            "        conclusion = os.environ['FIXTURE_TITLE_CI'] if workflow == 'pr-title.yml' else os.environ['FIXTURE_PR_CI']\n"
            "        if conclusion == 'missing': print(''); sys.exit(0)\n"
            "        status = 'in_progress' if conclusion == 'pending' else 'completed'\n"
            "        print(json.dumps({'id': run, 'status': status, 'conclusion': None if conclusion == 'pending' else conclusion, 'head_sha': sha, 'head_branch': 'automation/flake-lock', 'event': 'pull_request', 'path': '.github/workflows/' + ('other.yml' if os.environ['FIXTURE_WRONG_RUN_PATH'] == '1' else workflow)}))\n"
            "        sys.exit(0)\n"
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

    def git(self, *arguments, cwd=None, env=None):
        result = subprocess.run(["git", *arguments], cwd=cwd, text=True, capture_output=True, check=True,
                                env=(os.environ | env) if env else None)
        return result.stdout.strip()

    def update(
        self,
        *,
        change=True,
        event="workflow_dispatch",
        pr="",
        title_ci="success",
        branch_race=False,
        late_branch_race=False,
        pre_merge_main_race=False,
        wrong_pr_head=False,
        wrong_run_path=False,
        pr_ci="success",
        atomic_ready=False,
        atomic_wrong_head=False,
        app_token="dummy-secret",
    ):
        env = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "FIXTURE_CHANGE": str(int(change)),
            "FIXTURE_PR": pr,
            "FIXTURE_BRANCH_RACE": str(int(branch_race)),
            "FIXTURE_LATE_BRANCH_RACE": str(int(late_branch_race)),
            "FIXTURE_TITLE_CI": title_ci,
            "FIXTURE_ATOMIC_WRONG_HEAD": str(int(atomic_wrong_head)),
            "FIXTURE_PRE_MERGE_MAIN_RACE": str(int(pre_merge_main_race)),
            "FIXTURE_WRONG_PR_HEAD": str(int(wrong_pr_head)),
            "FIXTURE_WRONG_RUN_PATH": str(int(wrong_run_path)),
            "FIXTURE_PR_CI": pr_ci,
            "FIXTURE_ATOMIC_READY": str(int(atomic_ready)),
            "GH_AUTOMATION_APP_TOKEN": app_token,
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
        (self.root / "main-raced").unlink(missing_ok=True)
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

    def atomic_sha(self):
        return self.git("--git-dir", str(self.remote), "rev-parse", "automation/atomic-cleanup")


    def test_creates_validates_and_fast_forwards_main_to_same_sha(self):
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("--git-dir", str(self.remote), "show", "main:flake.lock"), lock_fixture("new"))
        self.assertEqual(self.main_sha(), self.branch_sha())
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests),
                         "App-authored PR checks should run without redundant dispatches")
        self.assertTrue(any(r[:2] == ["pr", "create"] for r in self.requests))
        self.assertFalse(any(r[:2] == ["pr", "merge"] and "--disable-auto" not in r for r in self.requests))

    def test_existing_pr_refreshes_without_duplicate_create(self):
        self.git("push", "origin", "HEAD:refs/heads/automation/flake-lock", cwd=self.checkout)
        result = self.update(pr="123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(r[:2] == ["pr", "create"] for r in self.requests))
        self.assertFalse(any(r[:2] == ["pr", "merge"] and "--disable-auto" not in r for r in self.requests))
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
        result = self.update(pr_ci="failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("concluded failure", result.stderr)
        self.assertEqual(self.main_sha(), self.main)

    def test_title_failure_does_not_publish_validated_lock(self):
        result = self.update(title_ci="failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.main_sha(), self.main)

    def test_branch_change_during_pr_creation_does_not_merge(self):
        result = self.update(late_branch_race=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Lock branch changed", result.stderr)
        self.assertEqual(self.main_sha(), self.main)

    def test_missing_pr_ci_prevents_merge(self):
        result = self.update(pr_ci="missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Timed out waiting for required PR workflow ci.yml", result.stderr)
        self.assertEqual(self.main_sha(), self.main)

    def test_main_race_after_final_check_rejects_atomic_merge(self):
        result = self.update(pre_merge_main_race=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / "main-raced").exists())
        self.assertIn("Atomic lock fast-forward was rejected", result.stderr)

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

    def test_required_pr_runs_pass_without_manual_approvals(self):
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(r[0] == "api" and any(a.endswith('/approve') for a in r)
                             for r in self.requests))
        self.assertEqual(self.main_sha(), self.branch_sha())

    def test_action_required_does_not_publish(self):
        result = self.update(pr_ci="action_required")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requests manual approval", result.stderr)
        self.assertEqual(self.main_sha(), self.main)

    def test_normal_pr_failure_cannot_publish(self):
        result = self.update(pr_ci="failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.main_sha(), self.main)

    def test_stale_pr_cannot_merge(self):
        result = self.update(wrong_pr_head=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.main_sha(), self.main)
        self.assertFalse(any(r[0] == "api" and any(a.endswith('/approve') for a in r) for r in self.requests))

    def test_unexpected_workflow_cannot_merge(self):
        result = self.update(wrong_run_path=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.main_sha(), self.main)
        self.assertFalse(any(r[0] == "api" and any(a.endswith('/approve') for a in r) for r in self.requests))

    def test_atomic_candidate_carries_cleanup_and_merges_exact_head(self):
        result = self.update(atomic_ready=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.main_sha(), self.main)
        self.assertEqual(self.git("--git-dir", str(self.remote), "show", "automation/atomic-cleanup:flake.lock"), lock_fixture("new"))
        self.assertNotEqual(subprocess.run(
            ["git", "--git-dir", str(self.remote), "cat-file", "-e",
             "automation/atomic-cleanup:modules/aspects/upstream/qbittorrent.nix"],
            capture_output=True).returncode, 0)
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))
        self.assertTrue(any("event=pull_request" in r and "ci.yml/runs" in str(r) for r in self.requests))
        self.assertTrue(any("event=pull_request" in r and "pr-title.yml/runs" in str(r) for r in self.requests))
        self.assertFalse(any(r[0] == "api" and any(a.endswith("/approve") for a in r)
                             for r in self.requests))
        self.assertTrue(any(r[:2] == ["pr", "merge"] and "--disable-auto" not in r
                            and "--match-head-commit" in r and "--auto" not in r
                            for r in self.requests))

    def test_failed_required_atomic_pr_checks_prevent_merge(self):
        result = self.update(atomic_ready=True, pr_ci="failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("--match-head-commit" in r for r in self.requests))
        self.assertFalse((self.root / "auto-merged").exists())

    def test_head_replaced_at_merge_is_rejected(self):
        (self.root / "replace-before-merge").touch()
        result = self.update(atomic_ready=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.main_sha(), self.main)
        self.assertFalse((self.root / "auto-merged").exists())
        merge = next(r for r in self.requests if "--match-head-commit" in r)
        self.assertNotEqual(merge[merge.index("--match-head-commit") + 1], self.atomic_sha())

    def test_recovery_disarms_before_rejecting_untrusted_candidate(self):
        self.assertEqual(self.update(atomic_ready=True).returncode, 0)
        self.git("--git-dir", str(self.remote), "update-ref", "-d",
                 "refs/heads/automation/atomic-cleanup-provenance")
        result = self.update(change=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "auto-merged").exists())
        self.assertEqual(self.requests[1], ["pr", "merge", "124", "--repo", "fixture/nix", "--disable-auto"])

    def test_failed_disarm_stops_recovery(self):
        self.assertEqual(self.update(atomic_ready=True).returncode, 0)
        (self.root / "disable-fails").touch()
        result = self.update(change=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.requests), 2)

    def test_failed_atomic_pr_checks_recover_without_rewriting_branch(self):
        first = self.update(atomic_ready=True, pr_ci="failure")
        self.assertNotEqual(first.returncode, 0)
        original = self.atomic_sha()
        self.git("switch", "main", cwd=self.checkout)
        second = self.update(change=False)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.main_sha(), self.main)
        self.assertEqual(self.atomic_sha(), original)
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))
        self.assertTrue(any(r[:2] == ["pr", "merge"] and "--match-head-commit" in r
                            for r in self.requests))

    def test_recovery_fetches_candidate_in_fresh_checkout(self):
        first = self.update(atomic_ready=True, pr_ci="failure")
        self.assertNotEqual(first.returncode, 0)
        fresh = self.root / "fresh"
        self.git("clone", "--single-branch", "--branch", "main", str(self.remote), str(fresh))
        self.git("config", "user.name", "fixture", cwd=fresh)
        self.git("config", "user.email", "fixture@example.test", cwd=fresh)
        self.checkout = fresh
        second = self.update(change=False)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))
        self.assertTrue(any(r[:2] == ["pr", "merge"] and "--disable-auto" not in r for r in self.requests))

    def test_merged_atomic_branch_is_safely_retired(self):
        first = self.update(atomic_ready=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        tip = self.git("--git-dir", str(self.remote), "rev-parse",
                       "automation/atomic-cleanup")
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
        self.assertFalse(subprocess.run(
            ["git", "--git-dir", str(self.remote), "show-ref", "--verify",
             "refs/heads/automation/atomic-cleanup-provenance"],
            capture_output=True).returncode == 0,
            "retirement must delete the provenance record with the branch")

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

    def test_stale_atomic_pr_head_cannot_merge(self):
        first = self.update(atomic_ready=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        second = self.update(atomic_wrong_head=True)
        self.assertNotEqual(second.returncode, 0)
        self.assertFalse(any(r[0] == "api" and any(a.endswith("/approve") for a in r)
                             for r in self.requests),
                         "a diverged PR head must never merge")

    def test_stale_atomic_lock_change_requires_new_candidate(self):
        self.assertEqual(self.update(atomic_ready=True).returncode, 0)
        tip = self.atomic_sha()
        self.git("switch", "--quiet", "main", cwd=self.checkout)
        (self.checkout / "flake.lock").write_text(lock_fixture("changed-after-publication"))
        self.git("add", "flake.lock", cwd=self.checkout)
        self.git("commit", "--quiet", "-m", "changed primary input", cwd=self.checkout)
        self.git("push", "--quiet", "origin", "main", cwd=self.checkout)
        self.main = self.git("rev-parse", "HEAD", cwd=self.checkout)
        second = self.update(change=False)
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("main changed flake.lock", second.stderr)
        self.assertEqual(self.atomic_sha(), tip)
        self.assertFalse(any(r[:2] == ["pr", "merge"] and "--match-head-commit" in r for r in self.requests))

    def test_stale_atomic_workaround_change_requires_new_candidate(self):
        self.assertEqual(self.update(atomic_ready=True).returncode, 0)
        tip = self.atomic_sha()
        self.git("switch", "--quiet", "main", cwd=self.checkout)
        p = self.checkout / "modules/aspects/upstream/qbittorrent.nix"
        p.write_text("edited on main\\n")
        self.git("add", str(p), cwd=self.checkout)
        self.git("commit", "--quiet", "-m", "edit workaround", cwd=self.checkout)
        self.git("push", "--quiet", "origin", "main", cwd=self.checkout)
        self.main = self.git("rev-parse", "HEAD", cwd=self.checkout)
        second = self.update(change=False)
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("main changed modules/aspects/upstream/qbittorrent.nix", second.stderr)
        self.assertEqual(self.atomic_sha(), tip)
        self.assertFalse(any(r[:2] == ["pr", "merge"] and "--match-head-commit" in r for r in self.requests))

    def test_tampered_atomic_tip_fails_closed(self):
        first = self.update(atomic_ready=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.git("fetch", "--quiet", "origin", "automation/atomic-cleanup", cwd=self.checkout)
        self.git("switch", "--quiet", "--detach", "FETCH_HEAD", cwd=self.checkout)
        arr = self.checkout / "modules/aspects/upstream/qbittorrent.nix"
        arr.parent.mkdir(parents=True, exist_ok=True)
        arr.write_text("tampered\n")
        self.git("add", ".", cwd=self.checkout)
        self.git("commit", "--quiet", "--amend", "--no-edit", cwd=self.checkout)
        tampered = self.git("rev-parse", "HEAD", cwd=self.checkout)
        self.git("push", "--quiet", "--force", "origin",
                 "HEAD:refs/heads/automation/atomic-cleanup", cwd=self.checkout)
        self.git("switch", "--quiet", "main", cwd=self.checkout)
        second = self.update()
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("requires human review", second.stderr)
        self.assertEqual(self.atomic_sha(), tampered,
                         "the tampered tip must not be overwritten")
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))
        self.assertFalse(any(r[:2] == ["pr", "merge"] and "--disable-auto" not in r for r in self.requests))

    def test_stacked_atomic_commit_fails_closed(self):
        first = self.update(atomic_ready=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.git("fetch", "--quiet", "origin", "automation/atomic-cleanup", cwd=self.checkout)
        self.git("switch", "--quiet", "--detach", "FETCH_HEAD", cwd=self.checkout)
        (self.checkout / "modules").mkdir(parents=True, exist_ok=True)
        (self.checkout / "modules/human-fixup.nix").write_text("fixup\n")
        self.git("add", ".", cwd=self.checkout)
        self.git("commit", "--quiet", "-m", "human fixup", cwd=self.checkout)
        stacked = self.git("rev-parse", "HEAD", cwd=self.checkout)
        self.git("push", "--quiet", "--force", "origin",
                 "HEAD:refs/heads/automation/atomic-cleanup", cwd=self.checkout)
        self.git("switch", "--quiet", "main", cwd=self.checkout)
        second = self.update()
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("requires human review", second.stderr)
        self.assertEqual(self.atomic_sha(), stacked,
                         "the changed candidate must not be overwritten")
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))
        self.assertFalse(any(r[:2] == ["pr", "merge"] and "--disable-auto" not in r for r in self.requests))

    def test_recovery_blocks_while_atomic_validation_pending(self):
        first = self.update(atomic_ready=True, pr_ci="failure")
        self.assertNotEqual(first.returncode, 0)
        self.git("switch", "main", cwd=self.checkout)
        second = self.update(change=False, pr_ci="pending")
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("Timed out waiting for required PR workflow ci.yml", second.stderr)
        self.assertFalse(any(r[:2] == ["pr", "merge"] and "--match-head-commit" in r for r in self.requests))

    def test_lockfile_only_amendment_rejected(self):
        first = self.update(atomic_ready=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        original = self.atomic_sha()
        self.git("fetch", "--quiet", "origin", "automation/atomic-cleanup", cwd=self.checkout)
        self.git("switch", "--quiet", "--detach", "FETCH_HEAD", cwd=self.checkout)
        lock = json.loads((self.checkout / "flake.lock").read_text())
        lock["nodes"]["nixpkgs_3"]["locked"]["rev"] = "evil"
        (self.checkout / "flake.lock").write_text(json.dumps(lock))
        self.git("add", "flake.lock", cwd=self.checkout)
        self.git("commit", "--quiet", "--amend", "--no-edit", cwd=self.checkout)
        tampered = self.git("rev-parse", "HEAD", cwd=self.checkout)
        self.assertNotEqual(tampered, original)
        self.git("push", "--quiet", "--force", "origin",
                 "HEAD:refs/heads/automation/atomic-cleanup", cwd=self.checkout)
        self.git("switch", "--quiet", "main", cwd=self.checkout)
        second = self.update()
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("requires human review", second.stderr)
        self.assertEqual(self.atomic_sha(), tampered,
                         "the tampered tip must not be overwritten")
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))
        self.assertFalse(any(r[:2] == ["pr", "merge"] and "--disable-auto" not in r for r in self.requests))
        record = json.loads(self.git(
            "--git-dir", str(self.remote), "show",
            "automation/atomic-cleanup-provenance:provenance.json", cwd=self.checkout))
        self.assertEqual(record["sha"], original)

    def test_forged_provenance_lock_rejected_by_replan(self):
        first = self.update(atomic_ready=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.git("fetch", "--quiet", "origin", "automation/atomic-cleanup", cwd=self.checkout)
        self.git("switch", "--quiet", "--detach", "FETCH_HEAD", cwd=self.checkout)
        lock = json.loads((self.checkout / "flake.lock").read_text())
        lock["nodes"]["nixpkgs_3"]["locked"]["rev"] = "evil"
        (self.checkout / "flake.lock").write_text(json.dumps(lock))
        self.git("add", "flake.lock", cwd=self.checkout)
        self.git("commit", "--quiet", "--amend", "--no-edit", cwd=self.checkout)
        tampered = self.git("rev-parse", "HEAD", cwd=self.checkout)
        self.git("push", "--quiet", "--force", "origin",
                 "HEAD:refs/heads/automation/atomic-cleanup", cwd=self.checkout)
        base = self.git("rev-parse", f"{tampered}^", cwd=self.checkout)
        lock_blob = self.git("rev-parse", f"{tampered}:flake.lock", cwd=self.checkout)
        prov_dir = self.root / "forged-prov"
        prov_repo = prov_dir / "repo"
        prov_dir.mkdir()
        self.git("init", "--quiet", str(prov_repo))
        (prov_repo / "provenance.json").write_text(json.dumps({
            "base": base, "sha": tampered,
            "watchers": "qbittorrent", "lock": lock_blob}))
        self.git("add", "provenance.json", cwd=prov_repo)
        self.git("-c", "user.name=fixture", "-c", "user.email=fixture@example.test",
                 "commit", "--quiet", "-m", "forged", cwd=prov_repo)
        forged = self.git("rev-parse", "HEAD", cwd=prov_repo)
        self.git("push", "--quiet", "--force", str(self.remote),
                 f"{forged}:refs/heads/automation/atomic-cleanup-provenance",
                 cwd=prov_repo)
        (self.root / "atomic-body").write_text(
            f"forged\n\n<!-- atomic-provenance base={base} sha={tampered} watchers=qbittorrent -->")
        self.git("switch", "--quiet", "main", cwd=self.checkout)
        second = self.update()
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("re-plan diverged", second.stderr)
        self.assertEqual(self.atomic_sha(), tampered,
                         "the forged tip must not be overwritten")
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))
        self.assertFalse(any(r[:2] == ["pr", "merge"] and "--disable-auto" not in r for r in self.requests))

    def test_identical_tree_new_sha_rejected(self):
        first = self.update(atomic_ready=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        original = self.atomic_sha()
        self.git("fetch", "--quiet", "origin", "automation/atomic-cleanup", cwd=self.checkout)
        self.git("switch", "--quiet", "--detach", "FETCH_HEAD", cwd=self.checkout)
        self.git("commit", "--quiet", "--amend", "--no-edit", cwd=self.checkout,
                 env={"GIT_COMMITTER_DATE": "2000-01-01T00:00:00+00:00"})
        restacked = self.git("rev-parse", "HEAD", cwd=self.checkout)
        self.assertNotEqual(restacked, original)
        self.assertEqual(
            self.git("rev-parse", f"{restacked}^{{tree}}", cwd=self.checkout),
            self.git("rev-parse", f"{original}^{{tree}}", cwd=self.checkout),
            "fixture must keep the tree identical")
        self.git("push", "--quiet", "--force", "origin",
                 "HEAD:refs/heads/automation/atomic-cleanup", cwd=self.checkout)
        self.git("switch", "--quiet", "main", cwd=self.checkout)
        second = self.update()
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("requires human review", second.stderr)
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))
        self.assertFalse(any(r[:2] == ["pr", "merge"] and "--disable-auto" not in r for r in self.requests))

    def test_missing_app_token_fails_closed_with_guidance(self):
        first = self.update(atomic_ready=True, pr_ci="failure")
        self.assertNotEqual(first.returncode, 0)
        self.git("switch", "main", cwd=self.checkout)
        second = self.update(change=False, app_token="")
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("GH_AUTOMATION_APP_TOKEN", second.stderr)
        self.assertFalse(any(r[:2] == ["pr", "merge"] and "--match-head-commit" in r for r in self.requests))

    def test_creation_records_provenance(self):
        result = self.update(atomic_ready=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        tip = self.atomic_sha()
        record = json.loads(self.git(
            "--git-dir", str(self.remote), "show",
            "automation/atomic-cleanup-provenance:provenance.json"))
        self.assertEqual(record["sha"], tip)
        self.assertEqual(record["base"], self.main)
        self.assertEqual(record["watchers"], "qbittorrent")
        self.assertEqual(record["lock"], self.git(
            "--git-dir", str(self.remote), "rev-parse", f"{tip}:flake.lock"))
        body = (self.root / "atomic-body").read_text()
        self.assertIn(f"sha={tip}", body)

    def test_missing_provenance_fails_closed(self):
        first = self.update(atomic_ready=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        tip = self.atomic_sha()
        self.git("--git-dir", str(self.remote), "update-ref", "-d",
                 "refs/heads/automation/atomic-cleanup-provenance")
        self.git("switch", "main", cwd=self.checkout)
        second = self.update(change=False)
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("provenance", second.stderr.lower())
        self.assertEqual(self.atomic_sha(), tip,
                         "the candidate must not be overwritten")
        self.assertFalse(any(r[:2] == ["workflow", "run"] for r in self.requests))
        self.assertFalse(any(r[:2] == ["pr", "merge"] and "--disable-auto" not in r for r in self.requests))

    def test_ci_run_name_includes_exact_dispatch_inputs(self):
        self.assertIn("run-name: >-", CI)
        self.assertIn("inputs.expected_sha", CI)
        self.assertIn("inputs.upstream_watcher", CI)


    def test_atomic_sentinel_drives_package_validation(self):
        self.assertIn("automation/atomic-cleanup", CI)
        self.assertIn("automation/atomic-cleanup", VALIDATION)
        self.assertIn("updated lock", VALIDATION)


    def test_lock_publisher_shell_is_parseable(self):
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
        self.assertEqual(VALIDATION.count("ref: ${{ github.sha }}"), checkout_count - 2)
        self.assertEqual(VALIDATION.count("ref: ${{ github.event.pull_request.head.sha || github.sha }}"), 2)
        self.assertIn("  pull_request:", CI)
        self.assertNotIn("paths-ignore:", CI)


if __name__ == "__main__":
    unittest.main()
