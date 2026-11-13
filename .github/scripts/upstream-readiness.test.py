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

    def test_ashell_cleanup_waits_for_pinned_aws_lc_dependency(self):
        no_fix = "nativeBuildInputs = [ pkg-config ]; buildInputs = [ pipewire udev ];"
        commented = "buildInputs = [ pipewire ]; # aws-lc may be needed later"
        fixed = "nativeBuildInputs = [ pkg-config ]; buildInputs = [ pipewire\n  aws-lc\n ];"
        for recipe, expected in ((no_fix, "waiting-source"),
                                 (commented, "waiting-source"),
                                 (fixed, "PINNED-READY")):
            with self.subTest(expected=expected), patch.object(watch, "source", return_value=recipe):
                self.assertEqual(watch.detect("ashell-aws-lc", LOCK), expected)

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

    def test_t3code_cleanup_completion_preserves_permanent_aspects(self):
        for name in ("t3code-connect", "t3code-split"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                relative, marker = watch.WORKAROUNDS[name]
                module = root / relative
                module.parent.mkdir(parents=True)
                module.write_text("{ homeManager = {}; }")
                with patch.object(watch, "ROOT", root), patch.object(watch, "detect") as detect:
                    self.assertEqual(watch.inspect(name, LOCK), "completed")
                    detect.assert_not_called()
                module.write_text(marker)
                with patch.object(watch, "ROOT", root), patch.object(watch, "detect", return_value="waiting-upstream"):
                    self.assertEqual(watch.inspect(name, LOCK), "waiting-upstream")


    def test_retired_t3code_bridge_stays_retired(self):
        root = Path(__file__).resolve().parents[2]
        # The watcher and its cleanup patch are gone, so the module does not
        # carry the version floor either.
        self.assertFalse((root / "modules/aspects/upstream/t3code-stable010.nix").exists())
        self.assertFalse((root / ".github/upstream/cleanup/t3code-stable010.patch").exists())

    def test_cleanup_recipes_are_well_formed_and_narrow(self):
        root = Path(__file__).resolve().parents[2]
        for recipe in sorted((root / '.github/upstream/cleanup').glob('*.patch')):
            with self.subTest(recipe=recipe.name):
                subprocess.run(['git', 'apply', '--numstat', str(recipe)], cwd=root, check=True, capture_output=True)
                patch_text = recipe.read_text()
                self.assertNotIn('diff --git a/flake.lock', patch_text)
                self.assertNotIn('diff --git a/.github/', patch_text)
                self.assertIn('diff --git a/modules/', patch_text)


    def test_relocated_upstream_cleanups_apply_and_are_owned(self):
        # Most post-lock workarounds live under upstream/. The GUI overrides
        # are inline in their owners; they also require exact cleanup recipes.
        # Check against the actual worktree so a moved helper and its cleanup
        # cannot drift apart and silently break publication.
        root = Path(__file__).resolve().parents[2]
        registry = json.loads((root / ".github/upstream/watchers.json").read_text())
        for name, spec in registry.items():
            if spec["mode"] != "post-lock":
                continue
            with self.subTest(watcher=name):
                relative, _marker = watch.WORKAROUNDS[name]
                self.assertTrue(relative.startswith("modules/aspects/upstream/") or
                                (name, relative) in {
                                    ("ashell-aws-lc", "modules/aspects/gui/niri.nix"),
                                    ("zapfast-openssl", "modules/aspects/gui/apps.nix"),
                                }, name)
                path = root / relative
                if not path.exists() or (_marker is not None and _marker not in path.read_text()):
                    # A previously applied cleanup may leave the permanent
                    # aspect but remove its temporary overlay marker. In both
                    # cases the watcher reports completion and must not try to
                    # reapply the removal patch.
                    self.assertEqual(watch.inspect(name, LOCK), "completed")
                    continue
                recipe = root / ".github/upstream/cleanup" / spec["cleanup"]
                subprocess.run(
                    ["git", "apply", "--check", str(recipe)],
                    cwd=root, check=True, capture_output=True, text=True,
                )



if __name__ == "__main__":
    unittest.main()

