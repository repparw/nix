#!/usr/bin/env python3
"""Exercise publication against a real disposable Git remote and a fake GitHub API."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("publisher", Path(__file__).with_name("upstream-publish.py"))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class Publication(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repo"
        self.remote = Path(self.temporary.name) / "remote.git"
        subprocess.run(["git", "init", "--bare", "--quiet", str(self.remote)], check=True)
        self.root.mkdir()
        self.git("init", "--quiet", "-b", "main")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.hooksPath", "/dev/null")
        module = self.root / "modules/fixture.nix"
        module.parent.mkdir()
        module.write_text("keep\nworkaround\n")
        recipes = self.root / ".github/upstream/cleanup"
        recipes.mkdir(parents=True)
        self.recipe = recipes / "fixture.patch"
        self.recipe.write_text("diff --git a/modules/fixture.nix b/modules/fixture.nix\n"
                               "--- a/modules/fixture.nix\n+++ b/modules/fixture.nix\n"
                               "@@ -1,2 +1 @@\n keep\n-workaround\n")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "base")
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "--quiet", "origin", "main")
        self.prs = []
        self.closed = []
        self.runs = {}
        self.dispatches = []
        self.comments = []
        self.automerges = []
        original = publisher.run

        def execute(*arguments, cwd=None, env=None):
            if arguments[0] != "gh":
                return original(*arguments, cwd=cwd or self.root, env=env)
            args = list(arguments[1:])
            if args[:2] == ["pr", "list"]:
                return json.dumps(self.prs if args[args.index("--state") + 1] == "open" else self.closed)
            if args[:2] == ["pr", "create"]:
                sha = self.git("ls-remote", "--heads", "origin", "automation/upstream-fixture").split()[0]
                self.prs = [{"number": 42, "headRefOid": sha}]
                return "https://github.com/fixture/repo/pull/42"
            if args[:2] == ["run", "list"]:
                commit = args[args.index("--commit") + 1] if "--commit" in args else None
                recorded = self.runs.get(args[args.index("--workflow") + 1], [])
                return json.dumps([r for r in recorded if commit is None or r["headSha"] == commit])
            if args[:2] == ["workflow", "run"]:
                self.dispatches.append(args)
                expected = args[[i for i, a in enumerate(args) if a.startswith("expected_sha=")][0]].split("=", 1)[1]
                self.runs[args[2]] = self.runs.get(args[2], []) + [{"headSha": expected}]
                return ""
            if args[0] == "api":
                return json.dumps([self.comments])
            if args[:2] == ["pr", "merge"]:
                self.automerges.append(args)
                return ""
            if args[:2] == ["issue", "comment"]:
                self.comments.append({"body": Path(args[args.index("--body-file") + 1]).read_text()})
                return ""
            raise AssertionError(arguments)

        self.addCleanup(patch.stopall)
        patch.object(publisher, "ROOT", self.root).start()
        patch.object(publisher, "run", execute).start()
        self.contract = {"mode": "post-lock", "cleanup": "fixture.patch"}

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, check=True,
                              capture_output=True, text=True).stdout.strip()

    def publish(self):
        return publisher.publish("fixture", self.contract, "fixture/repo")

    def test_fsr_candidates_notify_once_without_claiming_pin_readiness(self):
        registry = {"fsr4-rdna2": {"mode": "notify-only", "issue": 323}}
        readiness = {"fsr4-rdna2": "upstream-review-required:GE-Proton11-12"}
        first, failed = publisher.sweep(registry, readiness, "fixture/repo")
        self.assertFalse(failed)
        self.assertEqual(first["fsr4-rdna2"]["status"], "notified")
        self.assertIn("not confirmed support", self.comments[0]["body"])
        self.assertNotIn("pin contains the upstream fix", self.comments[0]["body"])
        second, failed = publisher.sweep(registry, readiness, "fixture/repo")
        self.assertFalse(failed)
        self.assertEqual(second["fsr4-rdna2"]["status"], "already-notified")
        self.assertEqual(len(self.comments), 1)
        publisher.sweep(registry, {"fsr4-rdna2": "upstream-review-required:GE-Proton11-13"}, "fixture/repo")
        self.assertEqual(len(self.comments), 2)
        self.assertEqual(self.prs, [])
        self.assertEqual(self.dispatches, [])


    def test_create_reuse_and_exact_sha_dispatch(self):
        first = self.publish()
        self.assertEqual(first["pr"], 42)
        self.assertEqual(len(self.dispatches), 2)
        for invocation in self.dispatches:
            self.assertIn(f"expected_sha={first['sha']}", invocation)
        self.assertIn("upstream_watcher=fixture", self.dispatches[1])
        self.assertEqual(self.git("show", f"{first['sha']}:modules/fixture.nix"), "keep")
        self.assertEqual((self.root / "modules/fixture.nix").read_text(), "keep\nworkaround\n")
        self.assertEqual(self.publish(), first)
        self.assertEqual(len(self.dispatches), 2)

    def test_recover_missing_dispatch_without_rewriting_branch(self):
        first = self.publish()
        self.runs.pop("ci.yml")
        self.assertEqual(self.publish()["sha"], first["sha"])
        self.assertEqual(len(self.dispatches), 3)
        self.assertEqual(self.dispatches[-1][2], "ci.yml")

    def test_recover_branch_before_pr_creation(self):
        first = self.publish()
        self.prs = []
        self.assertEqual(self.publish()["sha"], first["sha"])
        self.assertEqual(len(self.dispatches), 2)

    def test_publish_arms_automerge(self):
        first = self.publish()
        self.assertEqual(first["status"], "automerge-armed")
        self.assertEqual(self.automerges, [["pr", "merge", "42", "--repo", "fixture/repo", "--squash", "--auto"]])
        # Re-arming an already-armed candidate stays a success.
        self.assertEqual(self.publish(), first)

    def test_stale_candidate_refreshes_onto_current_main(self):
        first = self.publish()
        (self.root / "modules/unrelated.nix").write_text("later\n")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "main moved on")
        self.git("push", "--quiet", "origin", "main")
        second = self.publish()
        self.assertNotEqual(second["sha"], first["sha"])
        tip = self.git("ls-remote", "--heads", "origin", "automation/upstream-fixture").split()[0]
        self.assertEqual(tip, second["sha"])
        self.git("fetch", "--quiet", "origin",
                 f"+refs/heads/automation/upstream-fixture:refs/remotes/origin/automation/upstream-fixture")
        self.assertEqual(self.git("show", f"{second['sha']}:modules/fixture.nix"), "keep")
        self.assertEqual(self.git("show", f"{second['sha']}:modules/unrelated.nix"), "later")
        self.assertEqual(self.prs[0]["number"], 42, "the open PR must be reused")
        self.assertEqual(len(self.automerges), 2)
        self.assertEqual(len(self.dispatches), 4)
        for invocation in self.dispatches[-2:]:
            self.assertIn(f"expected_sha={second['sha']}", invocation)

    def test_tampered_candidate_requires_review(self):
        first = self.publish()
        # Simulate a human edit on the candidate branch: the tip no longer
        # equals the recipe applied to its parent.
        candidate_sha = first["sha"]
        clone = Path(self.temporary.name) / "tamper"
        subprocess.run(["git", "clone", "--quiet", "--reference", str(self.root),
                        str(self.remote), str(clone), "--branch", "automation/upstream-fixture"], check=True)
        (clone / "modules/fixture.nix").write_text("keep\nworkaround\nextra\n")
        subprocess.run(["git", "-C", str(clone), "add", "."], check=True)
        subprocess.run(["git", "-C", str(clone), "-c", "user.name=T", "-c", "user.email=t@t",
                        "-c", "core.hooksPath=/dev/null", "commit", "--quiet",
                        "--amend", "-m", "tampered"], check=True)
        subprocess.run(["git", "-C", str(clone), "push", "--quiet", "--force", "origin",
                        "automation/upstream-fixture"], check=True)
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(
            self.git("ls-remote", "--heads", "origin", "automation/upstream-fixture").split()[0],
            subprocess.run(["git", "-C", str(clone), "rev-parse", "HEAD"], check=True,
                           capture_output=True, text=True).stdout.strip(),
            "the tampered tip must not be overwritten")

    def test_stacked_commit_requires_review(self):
        self.publish()
        # A second commit on top of the candidate, even with an otherwise
        # clean tree, is not provably the recipe applied to its parent: the
        # recipe no longer re-applies onto the tip's parent, so publication
        # fails closed instead of overwriting the branch.
        clone = Path(self.temporary.name) / "stack"
        subprocess.run(["git", "clone", "--quiet", "--reference", str(self.root),
                        str(self.remote), str(clone), "--branch", "automation/upstream-fixture"], check=True)
        (clone / "modules/extra.nix").write_text("human\n")
        subprocess.run(["git", "-C", str(clone), "add", "."], check=True)
        subprocess.run(["git", "-C", str(clone), "-c", "user.name=T", "-c", "user.email=t@t",
                        "-c", "core.hooksPath=/dev/null", "commit", "--quiet",
                        "-m", "human fixup"], check=True)
        subprocess.run(["git", "-C", str(clone), "push", "--quiet", "origin",
                        "automation/upstream-fixture"], check=True)
        stacked = self.git("ls-remote", "--heads", "origin", "automation/upstream-fixture").split()[0]
        self.prs[0]["headRefOid"] = stacked
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertEqual(self.git("ls-remote", "--heads", "origin", "automation/upstream-fixture").split()[0],
                         stacked)
        self.assertEqual(len(self.automerges), 1)

    def test_conflicting_main_advance_fails_closed(self):
        first = self.publish()
        # Main reworks the patched lines, so the recipe matches neither the
        # new main nor the stale tip's parent reconstruction.
        (self.root / "modules/fixture.nix").write_text("keep\nreworked\n")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "main moved on")
        self.git("push", "--quiet", "origin", "main")
        # The recipe no longer applies to the new main: the stale candidate
        # must be left alone for review, never force-updated.
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertEqual(self.git("ls-remote", "--heads", "origin", "automation/upstream-fixture").split()[0], first["sha"])
        self.assertEqual(len(self.automerges), 1)

    def test_changed_recipe_refuses_to_overwrite(self):
        first = self.publish()
        self.recipe.write_text(self.recipe.read_text().replace("-workaround", "-different"))
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertEqual(self.git("ls-remote", "--heads", "origin", "automation/upstream-fixture").split()[0], first["sha"])
        self.assertEqual(len(self.dispatches), 2)

    def test_closed_candidate_is_not_reopened(self):
        first = self.publish()
        self.prs = []
        self.closed = [{"number": 42}]
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(self.git("ls-remote", "--heads", "origin", "automation/upstream-fixture").split()[0], first["sha"])
        self.assertEqual(len(self.dispatches), 2)

    def test_waiting_and_unavailable_never_publish(self):
        result, failed = publisher.sweep({"fixture": self.contract}, {"fixture": "waiting-upstream"}, "fixture/repo")
        self.assertFalse(failed)
        self.assertEqual(result["fixture"]["status"], "waiting-upstream")
        self.assertFalse(self.prs)
        result, failed = publisher.sweep({"fixture": self.contract}, {}, "fixture/repo")
        self.assertTrue(failed)
        self.assertFalse(self.prs)

    def test_closed_pr_with_deleted_branch_stays_deleted(self):
        self.publish()
        self.git("push", "--quiet", "origin", "--delete", "automation/upstream-fixture")
        self.prs = []
        self.closed = [{"number": 42}]
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(self.git("ls-remote", "--heads", "origin", "automation/upstream-fixture"), "")
        self.assertEqual(len(self.dispatches), 2)

    def test_one_conflict_does_not_block_other_watchers(self):
        registry = {"broken": {"mode": "post-lock", "cleanup": "missing.patch"},
                    "fixture": self.contract}
        result, failed = publisher.sweep(registry, {name: "PINNED-READY" for name in registry}, "fixture/repo")
        self.assertTrue(failed)
        self.assertEqual(result["fixture"]["pr"], 42)
        self.assertEqual(result["broken"]["status"], "needs-attention (FileNotFoundError)")

    def test_notification_is_durable_and_deduplicated(self):
        contract = {"issue": 7}
        self.assertEqual(publisher.notify("fixture", contract, "fixture/repo", "PINNED-READY")["status"], "notified")
        self.assertEqual(publisher.notify("fixture", contract, "fixture/repo", "PINNED-READY")["status"], "already-notified")
        self.assertEqual(len(self.comments), 1)


if __name__ == "__main__":
    unittest.main()

