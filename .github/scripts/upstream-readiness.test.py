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

    def test_completed_reads_checked_out_tree(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(watch, "ROOT", Path(directory)), patch.object(watch, "detect") as detect:
            self.assertEqual(watch.inspect("tasks-org", LOCK), "completed")
            detect.assert_not_called()

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
