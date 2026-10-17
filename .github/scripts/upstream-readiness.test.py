#!/usr/bin/env python3
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("readiness", Path(__file__).with_name("upstream-readiness.py"))
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)
LOCK = {"nodes": {"root": {"inputs": {"nixpkgs": "np", "home-manager": "hm"}}, "np": {"locked": {"rev": "nix-pin"}}, "hm": {"locked": {"rev": "hm-pin"}}}}


class Readiness(unittest.TestCase):
    def test_ancestry_including_exact_pin_and_wrong_merge_base(self):
        for status, base, expected in [("ahead", "fix", True), ("identical", "fix", True), ("behind", "fix", False), ("diverged", "fix", False), ("ahead", "other", False)]:
            with self.subTest(status=status, base=base), patch.object(watch, "api", return_value={"status": status, "merge_base_commit": {"sha": base}}):
                self.assertEqual(watch.contains("repo", "fix", "pin"), expected)

    def test_hm_waits_use_hm_pin(self):
        with patch.object(watch, "api", return_value={"merged": True, "merge_commit_sha": "fix"}), patch.object(watch, "contains", return_value=True) as contains:
            self.assertEqual(watch.detect("t3code-server", LOCK), "PINNED-READY")
            contains.assert_called_once_with("nix-community/home-manager", "fix", "hm-pin")

    def test_upstream_unmerged_and_pin_behind(self):
        with patch.object(watch, "api", return_value={"merged": False}):
            self.assertEqual(watch.detect("tasks-org", LOCK), "waiting-upstream")
        with patch.object(watch, "api", return_value={"merged": True, "merge_commit_sha": "fix"}), patch.object(watch, "contains", return_value=False):
            self.assertEqual(watch.detect("tasks-org", LOCK), "merged-not-pinned")

    def test_moonshine_requires_reload_guard_before_ready(self):
        # PR227 merged and pinned is not enough: the pinned source must also
        # carry the reload guard, or the test build must be retained.
        files = {
            "pkgs/by-name/mo/moonshine/package.nix": 'version = "0.16.1"; tag = "v${finalAttrs.version}";',
            "moonshine-core/src/session/compositor/mod.rs": "mod held_commits;",
            "moonshine-core/src/session/compositor/handlers.rs": "held_commits::hold_until_rendered",
            "moonshine-core/src/session/compositor/held_commits.rs": "DMA_BUF_IOCTL_EXPORT_SYNC_FILE",
            "moonshine-core/src/session/application.rs": "fn handle() { if id == unit_name { let s = current_unit_state(); } }",
        }
        with patch.object(watch, "api", return_value={"merged": True, "merge_commit_sha": "fix"}), \
                patch.object(watch, "package_contains", return_value=True), \
                patch.object(watch, "source", side_effect=lambda repo, path, ref: files[path]):
            self.assertEqual(watch.detect("moonshine-pr227", LOCK), "PINNED-READY")
        unguarded = dict(files, **{"moonshine-core/src/session/application.rs": "fn handle() { if id == unit_name { teardown(); } }"})
        with patch.object(watch, "api", return_value={"merged": True, "merge_commit_sha": "fix"}), \
                patch.object(watch, "package_contains", return_value=True), \
                patch.object(watch, "source", side_effect=lambda repo, path, ref: unguarded[path]):
            self.assertEqual(watch.detect("moonshine-pr227", LOCK), "waiting-source")
        with patch.object(watch, "api", return_value={"merged": True, "merge_commit_sha": "fix"}), \
                patch.object(watch, "package_contains", return_value=False):
            self.assertEqual(watch.detect("moonshine-pr227", LOCK), "merged-not-pinned")

    def test_unavailable_does_not_become_completed_or_ready(self):
        with patch.object(watch, "detect", side_effect=subprocess.CalledProcessError(1, "gh")):
            self.assertEqual(watch.inspect("nautilus-module", LOCK), "unavailable (CalledProcessError)")

    def test_packages_require_source_ancestry_not_release_date(self):
        with patch.object(watch, "source", return_value='version = "5.9.0"; tag = "release-${finalAttrs.version}";'), patch.object(watch, "contains", return_value=False) as contains:
            self.assertFalse(watch.package_contains("qbittorrent", "qbittorrent/qBittorrent", "fix", "pin"))
            contains.assert_called_once_with("qbittorrent/qBittorrent", "fix", "release-5.9.0")

    def test_version_tag_expression_is_resolved_exactly(self):
        self.assertEqual(watch.source_ref('version = "1.3.0"; tag = finalAttrs.version;'), "1.3.0")

    def test_cliamp_requires_both_attach_and_quit(self):
        with patch.object(watch, "source", side_effect=['version = "2.3.0"; tag = "v${finalAttrs.version}";', 'attachCommand()']):
            self.assertEqual(watch.detect("cliamp-attach", LOCK), "merged-not-pinned")
        with patch.object(watch, "source", side_effect=['rev = "source-sha";', 'attachCommand() quitCommand()']):
            self.assertEqual(watch.detect("cliamp-attach", LOCK), "PINNED-READY")

    def test_graphical_target_must_cover_all_unit_dependencies(self):
        good = 'PartOf = [ "graphical-session.target" ]; After = [ "graphical-session.target" ]; WantedBy = [ "graphical-session.target" ];'
        with patch.object(watch, "source", return_value=good) as source:
            self.assertEqual(watch.detect("voxtype-graphical", LOCK), "PINNED-READY")
            source.assert_called_once_with("nix-community/home-manager", "modules/services/voxtype.nix", "hm-pin")
        with patch.object(watch, "source", return_value=good.replace('WantedBy', 'Wrong')):
            self.assertEqual(watch.detect("voxtype-graphical", LOCK), "merged-not-pinned")

    def test_gamescope_requires_both_lookup_sites_and_flag_branch(self):
        site = 'if (queueInfo.flags) { VkDeviceQueueInfo2 q2; dispatch->GetDeviceQueue2(device, &q2, &queue); } else dispatch->GetDeviceQueue(device, family, j, &queue);'
        self.assertFalse(watch.flagged_queues_fixed('void GetDeviceQueue2();'))
        self.assertFalse(watch.flagged_queues_fixed(site))
        self.assertTrue(watch.flagged_queues_fixed(site + site))

    def test_gamescope_checks_raw_pin_without_repository_overlays(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / 'vkroots.h').write_text('void GetDeviceQueue2();')
            with patch.object(watch.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, directory)) as run:
                self.assertFalse(watch.gamescope_fixed())
            expression = run.call_args.args[0][-1]
            self.assertIn('f.inputs.nixpkgs.legacyPackages.x86_64-linux.gamescope', expression)
            self.assertNotIn('nixosConfigurations', expression)

    def test_gamescope_uses_unoverlaid_root_nixpkgs_input(self):
        # Regression for the false PINNED-READY when using Alpha's overlay.
        captured = {}
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out / "vkroots.h").write_text(
                "deviceDispatch->GetDeviceQueue(device, queueInfo.queueFamilyIndex, j, &queue);"
            )
            def fake_run(command, **kwargs):
                captured["expression"] = command[command.index("--expr") + 1]
                captured["env"] = kwargs["env"]
                return subprocess.CompletedProcess(command, 0, f"{out}\n", "")
            with patch.object(watch.subprocess, "run", side_effect=fake_run):
                self.assertFalse(watch.gamescope_fixed())
        self.assertIn("f.inputs.nixpkgs.legacyPackages.x86_64-linux.gamescope", captured["expression"])
        self.assertNotIn("nixosConfigurations", captured["expression"])
        self.assertEqual(captured["env"]["UPSTREAM_WATCH_ROOT"], str(watch.ROOT))

    def test_completed_reads_checked_out_tree(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(watch, "ROOT", Path(directory)), patch.object(watch, "detect") as detect:
            self.assertEqual(watch.inspect("tasks-org", LOCK), "completed")
            detect.assert_not_called()


    def test_t3code_nightly_v2_release_channel_and_pin_gates(self):
        stable = 'version = "0.0.46"; tag = "v0.0.46";'
        outdated = 'version = "0.0.45"; tag = "v0.0.45";'
        released = {"tag_name": "v0.0.46", "draft": False, "prerelease": False}
        def run(eligible, channel=stable, pinned=stable, verified=True):
            def api(endpoint):
                if endpoint.endswith("/releases/latest"):
                    return released
                if endpoint.endswith("/commits/nixos-unstable"):
                    return {"sha": "a" * 40}
                if "/releases/tags/" in endpoint:
                    return released if verified else {**released, "prerelease": True}
                raise AssertionError(endpoint)
            def source(repository, path, revision):
                self.assertEqual(path, watch.T3CODE_UNWRAPPED)
                return channel if revision == "a" * 40 else pinned
            with patch.object(watch, "api", side_effect=api), patch.object(
                watch, "source", side_effect=source
            ), patch.object(
                watch, "contains", side_effect=lambda _repo, _fix, tag: tag in eligible
            ):
                return watch.detect("t3code-nightly-v2", LOCK)

        self.assertEqual(run(set()), "waiting-upstream")
        self.assertEqual(run({"v0.0.46"}, channel=outdated), "waiting-unstable")
        self.assertEqual(run({"v0.0.46"}, pinned=outdated), "merged-not-pinned")
        self.assertEqual(run({"v0.0.46"}), "PINNED-READY")
        with self.assertRaises(ValueError):
            run({"v0.0.46"}, verified=False)

    def test_t3code_nightly_v2_never_accepts_a_prerelease_or_malformed_metadata(self):
        stable = 'version = "0.0.46"; tag = "v0.0.46";'
        with patch.object(watch, "api", return_value={
            "tag_name": "v0.0.46-nightly.20261012.3021",
            "draft": False, "prerelease": False
        }):
            with self.assertRaises(ValueError):
                watch.detect("t3code-nightly-v2", LOCK)
        with patch.object(watch, "source", return_value=stable):
            self.assertEqual(watch.t3code_stable_tag("pin"), "v0.0.46")
        for package in ['version = "0.0.46"; tag = "v0.0.46-preview";',
                        'version = "0.0.46-nightly"; tag = "v0.0.46-nightly";']:
            with patch.object(watch, "source", return_value=package):
                self.assertIsNone(watch.t3code_stable_tag("pin"))

    def test_t3code_nightly_v2_missing_upstream_metadata_fails_closed(self):
        with patch.object(watch, "api", return_value={}):
            with self.assertRaises(ValueError):
                watch.detect("t3code-nightly-v2", LOCK)

    def test_t3code_stable010_reuses_the_nightly_v2_gate(self):
        for status in ("waiting-upstream", "merged-not-pinned", "PINNED-READY"):
            with patch.object(watch, "t3code_nightly_v2_status", return_value=status) as gate:
                self.assertEqual(watch.detect("t3code-stable010", LOCK), status)
                gate.assert_called_once_with(LOCK)
        with patch.object(watch, "t3code_nightly_v2_status", side_effect=ValueError("boom")):
            with self.assertRaises(ValueError):
                watch.detect("t3code-stable010", LOCK)

    def test_cleanup_recipes_are_well_formed_and_narrow(self):
        root = Path(__file__).resolve().parents[2]
        for recipe in sorted((root / '.github/upstream/cleanup').glob('*.patch')):
            with self.subTest(recipe=recipe.name):
                subprocess.run(['git', 'apply', '--numstat', str(recipe)], cwd=root, check=True, capture_output=True)
                patch_text = recipe.read_text()
                self.assertNotIn('diff --git a/flake.lock', patch_text)
                self.assertNotIn('diff --git a/.github/', patch_text)
                self.assertIn('diff --git a/modules/', patch_text)


if __name__ == "__main__":
    unittest.main()
