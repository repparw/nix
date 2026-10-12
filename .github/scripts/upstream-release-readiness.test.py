#!/usr/bin/env python3
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "release_readiness", Path(__file__).with_name("upstream-release-readiness.py")
)
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)

TESTED_COMMIT = "b" * 40
PIN_REV = "a" * 40
CHANNEL_REV = "c" * 40
BRANCH = "nixos-unstable"
LOCK = {"nodes": {"root": {"inputs": {"nixpkgs": "np"}}, "np": {"locked": {"rev": PIN_REV}}}}


def package(version, owner="anomalyco", repo="opencode"):
    """A by-name package.nix shape matching the real opencode packaging."""
    return (
        f'version = "{version}";\n'
        "src = fetchFromGitHub {\n"
        f'  owner = "{owner}";\n'
        f'  repo = "{repo}";\n'
        '  tag = "v${finalAttrs.version}";\n'
        "};\n"
    )


class Detector(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "flake.nix").write_text(f'nixpkgs.url = "github:NixOS/nixpkgs/{BRANCH}";\n')
        (self.root / "flake.lock").write_text(json.dumps(LOCK))
        root_patch = patch.object(watch, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)

    def detector(self, sources, tested_commit=TESTED_COMMIT, channel_rev=CHANNEL_REV, pr_evidence=None):
        """sources: {(revision, attr): text}; missing entries are absent attrs."""

        def try_source(repository, path, revision):
            return sources.get((revision, path.split("/")[3]))

        def api(endpoint):
            if endpoint == f"repos/{watch.UPSTREAM}/commits/{watch.TESTED_TAG}":
                if tested_commit is None:
                    raise subprocess.CalledProcessError(1, "gh api", stderr="gh: HTTP 404: Not Found")
                return {"sha": tested_commit}
            if endpoint == f"repos/NixOS/nixpkgs/branches/{BRANCH}":
                return {"commit": {"sha": channel_rev}}
            if "/compare/" in endpoint:
                if not endpoint.startswith(f"repos/{watch.UPSTREAM}/compare/"):
                    raise AssertionError(f"package source ancestry must use {watch.UPSTREAM}: {endpoint}")
                ref = endpoint.rsplit("...", 1)[1]
                status = {"v2.0.26": "identical", "v2.0.27": "ahead", "v2.0.25": "behind"}.get(ref, "diverged")
                return {"status": status, "merge_base_commit": {"sha": TESTED_COMMIT if status != "diverged" else "d" * 40}}
            raise AssertionError(f"unexpected endpoint {endpoint}")

        pr_patch = patch.object(watch, "packaging_pr_evidence", return_value=pr_evidence or [])
        pr_patch.start()
        self.addCleanup(pr_patch.stop)
        api_patch = patch.object(watch, "api", side_effect=api)
        api_patch.start()
        self.addCleanup(api_patch.stop)
        source_patch = patch.object(watch, "try_source", side_effect=try_source)
        source_patch.start()
        self.addCleanup(source_patch.stop)
        return watch

    def inspect(self, sources, overlay=False, **kwargs):
        if overlay:
            (self.root / watch.OVERLAY_MARKER).parent.mkdir(parents=True, exist_ok=True)
            (self.root / watch.OVERLAY_MARKER).write_text("final: prev: { }\n")
        return self.detector(sources, **kwargs).inspect(watch.WATCHER, LOCK)

    def test_branch_is_parsed_from_flake_nix_not_hardcoded(self):
        self.assertEqual(watch.flake_branch(), BRANCH)
        (self.root / "flake.nix").write_text('nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";\n')
        self.assertEqual(watch.flake_branch(), "nixos-unstable-small")
        (self.root / "flake.nix").write_text('nixpkgs.url = "github:NixOS/nixpkgs";\n')
        with self.assertRaises(ValueError):
            watch.flake_branch()

    def test_pin_revision_uses_root_lock_input_and_validates(self):
        self.assertEqual(watch.pin_revision(LOCK), PIN_REV)
        for lock in [
            {"nodes": {"root": {"inputs": {"nixpkgs": "np"}}, "np": {"locked": {"rev": "short"}}}},
            {"nodes": {"root": {"inputs": {}}}},
        ]:
            with self.subTest(lock=lock), self.assertRaises((ValueError, KeyError)):
                watch.pin_revision(lock)

    def test_transport_failure_fails_closed(self):
        error = subprocess.CalledProcessError(1, "gh api", stderr="connection refused")
        with patch.object(watch, "api", side_effect=error), patch.object(watch, "try_source", side_effect=error):
            result = watch.inspect(watch.WATCHER, LOCK)
        self.assertTrue(result["status"].startswith("unavailable"))
        self.assertNotIn("token", json.dumps(result).lower())
        # A transport failure after the tested tag resolves must also fail closed.
        with patch.object(
            watch, "api", side_effect=[{"sha": TESTED_COMMIT}, {"commit": {"sha": CHANNEL_REV}}, error, error, error]
        ), patch.object(watch, "try_source", side_effect=error):
            result = watch.inspect(watch.WATCHER, LOCK)
        self.assertTrue(result["status"].startswith("unavailable"))

    def test_parser_failure_fails_closed(self):
        result = self.inspect({(CHANNEL_REV, "opencode"): 'src = fetchTarball "x";'})
        self.assertEqual(result["status"], "unavailable (ValueError)")

    def test_prerelease_or_suffixed_versions_fail_closed(self):
        for version in ["2.0.26-beta", "2.0.26-unstable-20261012", "2"]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                watch.parse_package(package(version))

    def test_unknown_package_source_fails_closed(self):
        forked = {(CHANNEL_REV, "opencode2"): package("2.0.26", owner="someone-else")}
        self.assertEqual(self.inspect(forked)["status"], "unavailable (ValueError)")
        pinned = {(PIN_REV, "opencode2"): package("2.0.27", repo="opencode-fork")}
        self.assertEqual(self.inspect(pinned)["status"], "unavailable (ValueError)")

    def test_tested_tag_missing_upstream_waits_upstream(self):
        result = self.inspect({}, tested_commit=None)
        self.assertEqual(result["status"], "waiting-upstream")
        self.assertIsNone(result["tested"]["commit"])

    def test_tested_tag_metadata_is_invalidated_fail_closed(self):
        with patch.object(watch, "api", return_value={"sha": "nothex"}):
            with self.assertRaises(ValueError):
                watch.tested_tag_commit()

    def test_older_stable_missing_merge_never_becomes_ready(self):
        older = {
            (CHANNEL_REV, "opencode2"): package("2.0.25"),
            (PIN_REV, "opencode2"): package("2.0.25"),
        }
        self.assertEqual(self.inspect(older)["status"], "waiting-upstream")
        merged = [{"number": 569770, "state": "merged", "merged": True, "merge_commit_sha": "f" * 40, "branch_reachable": "contains"}]
        self.assertEqual(self.inspect(older, pr_evidence=merged)["status"], "waiting-unstable")

    def test_channel_ahead_pin_behind_waits_for_pin(self):
        ahead = {
            (CHANNEL_REV, "opencode2"): package("2.0.27"),
            (PIN_REV, "opencode"): package("1.19.0"),
        }
        self.assertEqual(self.inspect(ahead)["status"], "merged-not-pinned")
        older_pin = {
            (CHANNEL_REV, "opencode2"): package("2.0.27"),
            (PIN_REV, "opencode2"): package("2.0.25"),
        }
        self.assertEqual(self.inspect(older_pin)["status"], "merged-not-pinned")

    def test_ready_requires_real_v2_source_in_channel_and_pin(self):
        ready = {
            (CHANNEL_REV, "opencode2"): package("2.0.27"),
            (PIN_REV, "opencode2"): package("2.0.26"),
        }
        with patch.object(watch, "packaging_pr_evidence") as prs:
            self.assertEqual(self.inspect(ready, overlay=True)["status"], "PINNED-READY")
            prs.assert_not_called()

    def test_pr_merge_alone_never_yields_ready_or_completed(self):
        merged = [
            {"number": 569770, "state": "merged", "merged": True, "merge_commit_sha": "f" * 40, "branch_reachable": "contains"},
            {"number": 572946, "state": "merged", "merged": True, "merge_commit_sha": "e" * 40, "branch_reachable": "contains"},
        ]
        v1 = {(CHANNEL_REV, "opencode"): package("1.19.0"), (PIN_REV, "opencode"): package("1.19.0")}
        self.assertEqual(self.inspect(v1, pr_evidence=merged)["status"], "waiting-unstable")

    def test_completed_requires_overlay_absence_and_pinned_real_v2(self):
        ready = {
            (CHANNEL_REV, "opencode2"): package("2.0.26"),
            (PIN_REV, "opencode2"): package("2.0.26"),
        }
        self.assertEqual(self.inspect(ready)["status"], "completed")
        self.assertEqual(self.inspect(ready, overlay=True)["status"], "PINNED-READY")
        v1 = {(CHANNEL_REV, "opencode"): package("1.19.0"), (PIN_REV, "opencode"): package("1.19.0")}
        self.assertEqual(self.inspect(v1)["status"], "waiting-upstream")

    def test_candidate_attrs_are_probed_in_priority_order(self):
        with patch.object(watch, "contains", return_value=True) as ancestry:
            with patch.object(watch, "try_source", side_effect=lambda _r, path, _rev: package("1.19.0") if path.endswith("opencode/package.nix") else None):
                state = watch.probe_revision("NixOS/nixpkgs", CHANNEL_REV, TESTED_COMMIT)
            self.assertEqual(state["attr"], "opencode")
            self.assertEqual(state["version"], "1.19.0")
            self.assertFalse(state["real_v2"])
            ancestry.assert_not_called()
            self.assertEqual(state["candidates"], {"opencode2": None, "opencode_2": None, "opencode": "1.19.0"})

            with patch.object(watch, "try_source", side_effect=lambda _r, path, _rev: package("2.0.26") if path.endswith("opencode_2/package.nix") else None):
                state = watch.probe_revision("NixOS/nixpkgs", CHANNEL_REV, TESTED_COMMIT)
            self.assertEqual((state["attr"], state["version"], state["real_v2"]), ("opencode_2", "2.0.26", True))

            both = lambda _r, path, _rev: package("2.0.27" if path.endswith("opencode2/package.nix") else "2.0.26")
            with patch.object(watch, "try_source", side_effect=both):
                state = watch.probe_revision("NixOS/nixpkgs", CHANNEL_REV, TESTED_COMMIT)
            self.assertEqual((state["attr"], state["version"]), ("opencode2", "2.0.27"))

    def test_tag_lineage_gates_on_tested_commit_ancestry(self):
        for status, base, expected in [
            ("ahead", TESTED_COMMIT, True),
            ("identical", TESTED_COMMIT, True),
            ("behind", TESTED_COMMIT, False),
            ("ahead", "other", False),
        ]:
            with self.subTest(status=status, base=base), patch.object(
                watch, "api", return_value={"status": status, "merge_base_commit": {"sha": base}}
            ):
                self.assertEqual(watch.contains("repo", TESTED_COMMIT, "v2.0.27"), expected)

    def test_try_source_distinguishes_absent_attr_from_transport_failure(self):
        def run_404(*_args, **_kwargs):
            return subprocess.CompletedProcess([], 1, stdout="", stderr="gh: HTTP 404: Not Found")

        with patch.object(watch, "subprocess") as subprocess_module:
            subprocess_module.run.side_effect = run_404
            self.assertIsNone(watch.try_source("NixOS/nixpkgs", "pkgs/by-name/op/opencode2/package.nix", PIN_REV))

        def run_refused(*_args, **_kwargs):
            return subprocess.CompletedProcess([], 1, stdout="", stderr="connection refused")

        with patch.object(watch, "subprocess") as subprocess_module:
            subprocess_module.run.side_effect = run_refused
            with self.assertRaises(subprocess.CalledProcessError):
                watch.try_source("NixOS/nixpkgs", "pkgs/by-name/op/opencode2/package.nix", PIN_REV)

    def test_packaging_prs_use_nh_with_gh_token_and_reachability(self):
        def run(command, **kwargs):
            if command == ["gh", "auth", "token"]:
                self.assertEqual(kwargs["capture_output"], True)
                return subprocess.CompletedProcess([], 0, stdout="secret-token\n", stderr="")
            self.assertEqual(command[0], "nh")
            self.assertEqual(command[1:3], ["search", "prs"])
            self.assertEqual(command[4:], ["--days", "400", "--json"])
            number = int(command[3])
            self.assertIn(number, watch.PACKAGING_PRS)
            self.assertEqual(kwargs["env"]["GH_TOKEN"], "secret-token")
            return subprocess.CompletedProcess([], 0, stdout=json.dumps({
                "results": [
                    {
                        "number": number,
                        "state": "merged",
                        "merge_commit_sha": "f" * 40,
                        "reachability": [{"branch": BRANCH, "status": "contains"}],
                    }
                ]
            }), stderr="")

        with patch.object(watch, "_TOKEN_ENV", None):
            with patch.object(watch.subprocess, "run", side_effect=run):
                evidence = watch.packaging_pr_evidence(BRANCH)
        self.assertEqual(evidence, [
            {
                "number": number,
                "state": "merged",
                "merged": True,
                "merge_commit_sha": "f" * 40,
                "branch_reachable": "contains",
            }
            for number in watch.PACKAGING_PRS
        ])

    def test_packaging_prs_fail_closed_when_report_is_incomplete(self):
        with patch.object(watch, "_TOKEN_ENV", {}):
            with patch.object(watch.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout=json.dumps({"results": []}), stderr="")):
                with self.assertRaises(ValueError):
                    watch.packaging_pr_evidence(BRANCH)
            with patch.object(watch.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "nh")):
                with self.assertRaises(subprocess.CalledProcessError):
                    watch.packaging_pr_evidence(BRANCH)

    def test_json_metadata_carries_status_and_chosen_versions_refs(self):
        ready = {
            (CHANNEL_REV, "opencode2"): package("2.0.27"),
            (PIN_REV, "opencode_2"): package("2.0.26"),
        }
        evidence = self.inspect(ready, overlay=True)
        self.assertEqual(evidence["status"], "PINNED-READY")
        self.assertEqual(
            evidence["tested"],
            {"repo": "anomalyco/opencode", "version": "2.0.26", "tag": "v2.0.26", "commit": TESTED_COMMIT},
        )
        self.assertEqual(evidence["flake"], {"input": "nixpkgs", "branch": BRANCH})
        self.assertEqual(
            [evidence["channel"][key] for key in ("revision", "attr", "version", "source_ref", "source_repo", "real_v2")],
            [CHANNEL_REV, "opencode2", "2.0.27", "v2.0.27", "anomalyco/opencode", True],
        )
        self.assertEqual(
            [evidence["pin"][key] for key in ("revision", "attr", "version", "source_ref", "real_v2")],
            [PIN_REV, "opencode_2", "2.0.26", "v2.0.26", True],
        )
        self.assertEqual(evidence["overlay"], {"path": "modules/_packages/opencode-v2.nix", "present": True})

    def test_unknown_watcher_is_rejected(self):
        with self.assertRaises(ValueError):
            watch.inspect("t3code-nightly-v2", LOCK)

    def test_parse_resolves_tag_templates_and_literal_revs(self):
        self.assertEqual(watch.parse_package(package("2.0.26"))["ref"], "v2.0.26")
        self.assertEqual(watch.parse_package('version = "2.0.26"; tag = finalAttrs.version;')["ref"], "2.0.26")
        self.assertEqual(watch.parse_package('version = "2.0.26"; rev = "abc123";')["ref"], "abc123")
        with self.assertRaises(ValueError):
            watch.parse_package('version = "2.0.26";')


if __name__ == "__main__":
    unittest.main()
