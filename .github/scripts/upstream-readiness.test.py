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
    def fsr_spec(self, commit=None):
        return patch.object(watch.Path, "read_text", return_value=json.dumps({
            "fsr4-rdna2": {"baseline_release": "GE-Proton11-11", "support_commit": commit}}))

    def test_fsr_release_notes_only_request_review_never_ready(self):
        def release(tag, body, **extra):
            return dict(tag_name=tag, body=body, draft=False, prerelease=False, **extra)
        releases = [release("GE-Proton11-11", "FSR4 support"),
                    release("GE-Proton11-12", "Video playback fixes"),
                    release("GE-Proton11-13", "FSR 4.1 RDNA2 support")]
        with self.fsr_spec(), patch.object(watch, "api", return_value=releases), \
                patch.object(watch, "ge_package_contains") as probe:
            self.assertEqual(watch.detect("fsr4-rdna2", LOCK),
                             "upstream-review-required:GE-Proton11-13")
            probe.assert_not_called()
        releases[-1]["prerelease"] = True
        with self.fsr_spec(), patch.object(watch, "api", return_value=releases):
            self.assertEqual(watch.detect("fsr4-rdna2", LOCK), "waiting-upstream")
        with self.fsr_spec(), patch.object(watch, "api", return_value=[releases[0]] * 100):
            self.assertEqual(watch.detect("fsr4-rdna2", LOCK), "waiting-upstream")

    def test_fsr_ancestry_gates_channel_and_pin_independently(self):
        commit = "b" * 40
        lock = json.loads(json.dumps(LOCK))
        lock["nodes"]["np"]["original"] = {"ref": "nixos-unstable"}
        def api(endpoint):
            if endpoint.endswith("releases/latest"):
                return {"tag_name": "GE-Proton11-12", "draft": False, "prerelease": False}
            return {"sha": "a" * 40}
        for package_results, expected in (([False], "waiting-unstable"),
                                          ([True, False], "merged-not-pinned"),
                                          ([True, True], "PINNED-READY")):
            with self.subTest(expected=expected), self.fsr_spec(commit), \
                    patch.object(watch, "api", side_effect=api), \
                    patch.object(watch, "contains", return_value=True), \
                    patch.object(watch, "ge_package_contains", side_effect=package_results) as probe:
                self.assertEqual(watch.detect("fsr4-rdna2", lock), expected)
                self.assertEqual(probe.call_args_list[0].args, ("a" * 40, commit))
                if len(package_results) == 2:
                    self.assertEqual(probe.call_args_list[1].args, ("nix-pin", commit))
        with self.fsr_spec(commit), patch.object(watch, "api", side_effect=api), \
                patch.object(watch, "contains", return_value=False), \
                patch.object(watch, "ge_package_contains") as probe:
            self.assertEqual(watch.detect("fsr4-rdna2", lock), "waiting-upstream")
            probe.assert_not_called()

    def test_fsr_rejects_unknown_archive_and_unstable_packaged_release(self):
        archive = ('https://github.com/GloriousEggroll/proton-ge-custom/releases/'
                   'download/${finalAttrs.version}/${finalAttrs.version}-x86_64.tar.gz')
        package = 'version = "GE-Proton11-12"; url = "' + archive + '";'
        with patch.object(watch, "source", return_value=package.replace("github.com", "example.com")):
            with self.assertRaises(ValueError):
                watch.ge_package_contains("pin", "b" * 40)
        with patch.object(watch, "source", return_value=package), patch.object(watch, "api", return_value={
                "tag_name": "GE-Proton11-12", "draft": False, "prerelease": True}):
            with self.assertRaises(ValueError):
                watch.ge_package_contains("pin", "b" * 40)

    def test_fsr_api_errors_and_invalid_evidence_fail_closed(self):
        for commit, result in (("short", []), (None, [{}]), (None, [{}] * 100)):
            with self.subTest(commit=commit), self.fsr_spec(commit), \
                    patch.object(watch, "api", return_value=result):
                self.assertTrue(watch.inspect("fsr4-rdna2", LOCK).startswith("unavailable"))

    def test_tridactyl_waits_for_the_selected_extension_release(self):
        lock = {"nodes": {"root": {"inputs": {"firefox-addons": "addons"}},
                          "addons": {"locked": {"rev": "addon-pin"}}}}
        selected = {"revision": "addon-pin", "addons": [
            {"version": "1.25.1", "addonId": "tridactyl.vim@cmcaine.co.uk"}]}
        merged = {"merged": True, "merge_commit_sha": "fix"}
        with patch.object(watch, "api", return_value={"merged": False}), \
                patch.object(watch.subprocess, "run") as run:
            self.assertEqual(watch.detect("tridactyl-reader", lock), "waiting-upstream")
            run.assert_not_called()
        for included, expected in ((False, "merged-not-pinned"), (True, "PINNED-READY")):
            with self.subTest(included=included), \
                    patch.object(watch, "api", return_value=merged), \
                    patch.object(watch.subprocess, "run", return_value=subprocess.CompletedProcess(
                        [], 0, json.dumps(selected))), \
                    patch.object(watch, "contains", return_value=included) as contains:
                self.assertEqual(watch.detect("tridactyl-reader", lock), expected)
                contains.assert_called_once_with("tridactyl/tridactyl", "fix", "1.25.1")

    def test_tridactyl_rejects_wrong_pin_ambiguous_and_preview_metadata(self):
        lock = {"nodes": {"root": {"inputs": {"firefox-addons": "addons"}},
                          "addons": {"locked": {"rev": "addon-pin"}}}}
        addon = {"version": "1.25.1", "addonId": "tridactyl.vim@cmcaine.co.uk"}
        for revision, addons in (("wrong-pin", [addon]), ("addon-pin", []),
                                 ("addon-pin", [addon, addon]),
                                 ("addon-pin", [{**addon, "version": "1.26.0pre"}]),
                                 ("addon-pin", [{**addon, "addonId": "other"}])):
            selected = {"revision": revision, "addons": addons}
            with self.subTest(selected=selected), \
                    patch.object(watch, "api", return_value={"merged": True}), \
                    patch.object(watch.subprocess, "run", return_value=subprocess.CompletedProcess(
                        [], 0, json.dumps(selected))), patch.object(watch, "contains") as contains:
                self.assertEqual(watch.inspect("tridactyl-reader", lock), "unavailable (ValueError)")
                contains.assert_not_called()

    def test_ancestry_including_exact_pin_and_wrong_merge_base(self):
        for status, base, expected in [("ahead", "fix", True), ("identical", "fix", True), ("behind", "fix", False), ("diverged", "fix", False), ("ahead", "other", False)]:
            with self.subTest(status=status, base=base), patch.object(watch, "api", return_value={"status": status, "merge_base_commit": {"sha": base}}):
                self.assertEqual(watch.contains("repo", "fix", "pin"), expected)

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

    def test_moonshine_watcher_uses_pinned_package_version_not_wsi(self):
        for version, expected in (("0.17.2", "merged-not-pinned"),
                                  ("0.18.0", "PINNED-READY"),
                                  ("0.18.1", "PINNED-READY"),
                                  ("0.19.0", "PINNED-READY")):
            package = ('pname = "ferriscope-wsi"; version = "0.1.0";\n'
                       f'pname = "moonshine"; version = "{version}";')
            with self.subTest(version=version), \
                    patch.object(watch, "source", return_value=package) as fetched:
                self.assertEqual(watch.detect("moonshine-0-18", LOCK), expected)
                fetched.assert_called_once_with(
                    "NixOS/nixpkgs", "pkgs/by-name/mo/moonshine/package.nix", "nix-pin")

    def test_moonshine_watcher_rejects_ambiguous_package_metadata(self):
        for package in ('version = "0.18.0";',
                        'pname = "ferriscope-wsi"; version = "0.18.0";',
                        'pname = "moonshine"; version = "0.18.0-beta";',
                        'pname = "moonshine"; version = "0.18.0";\n'
                        'pname = "moonshine"; version = "0.18.0";'):
            with self.subTest(package=package), \
                    patch.object(watch, "source", return_value=package):
                with self.assertRaises(ValueError):
                    watch.moonshine_pinned_version("nix-pin")

    def test_t3code_0_1_13_requires_source_ancestry_and_distinguishes_pr_state(self):
        unwrapped_old = 'version = "0.1.8"; tag = "v${finalAttrs.version}";'
        unwrapped_new = 'version = "0.1.13"; tag = "v${finalAttrs.version}";'
        with patch.object(watch, "source", return_value=unwrapped_new) as fetched, \
                patch.object(watch, "contains", return_value=True) as contains, \
                patch.object(watch, "api") as api:
            self.assertEqual(watch.detect("t3code-0-1-13", LOCK), "PINNED-READY")
            fetched.assert_called_once_with("NixOS/nixpkgs", watch.T3CODE_UNWRAPPED, "nix-pin")
            contains.assert_called_once_with("pingdotgg/t3code", watch.T3CODE_0_1_13_COMMIT, "v0.1.13")
            api.assert_not_called()
        for merged, expected in ((False, "waiting-upstream"), (True, "merged-not-pinned")):
            with self.subTest(merged=merged), \
                    patch.object(watch, "source", return_value=unwrapped_old), \
                    patch.object(watch, "contains", return_value=False) as contains, \
                    patch.object(watch, "api", return_value={"merged": merged}) as api:
                self.assertEqual(watch.detect("t3code-0-1-13", LOCK), expected)
                contains.assert_called_once_with("pingdotgg/t3code", watch.T3CODE_0_1_13_COMMIT, "v0.1.8")
                api.assert_called_once_with("repos/NixOS/nixpkgs/pulls/589125")

    def test_t3code_0_1_13_fails_closed_on_missing_source_metadata(self):
        with patch.object(watch, "source", return_value='pname = "t3code-unwrapped";'):
            self.assertEqual(watch.inspect("t3code-0-1-13", LOCK), "unavailable (ValueError)")

    def test_completed_reads_checked_out_tree(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(watch, "ROOT", Path(directory)), patch.object(watch, "detect") as detect:
            self.assertEqual(watch.inspect("tasks-org", LOCK), "completed")
            detect.assert_not_called()

    def test_post_lock_workarounds_have_one_removable_file(self):
        root = Path(__file__).resolve().parents[2]
        registry = json.loads((root / ".github/upstream/watchers.json").read_text())
        for name, spec in registry.items():
            if spec["mode"] != "post-lock":
                continue
            with self.subTest(watcher=name):
                relative = f"modules/aspects/upstream/{name}.nix"
                self.assertEqual(watch.WORKAROUNDS[name][0], relative)
                self.assertNotIn("cleanup", spec)
                if not (root / relative).exists():
                    self.assertEqual(watch.inspect(name, LOCK), "completed")


if __name__ == "__main__":
    unittest.main()

