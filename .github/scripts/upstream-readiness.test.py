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
    def hermes_lock(self):
        return {"nodes": {"root": {"inputs": {"hermes-agent": "selected-hermes"}},
                          "selected-hermes": {"locked": {"rev": "hermes-pin"}}}}

    def test_hermes_uses_exact_fix_and_selected_input_source(self):
        provider = "class TerminalEnvironmentProvider:\n    supports_streams: bool = False\n    @property\n    def default_cwd(self): pass\n"
        pr = {"merged": True, "merge_commit_sha": watch.HERMES_CUA_FIX}
        with patch.object(watch, "api", return_value={"merged": False}):
            self.assertEqual(watch.detect("hermes-cua-version", self.hermes_lock()), "waiting-upstream")
        for included, text, expected in ((False, provider, "merged-not-pinned"),
                (True, "# supports_streams default_cwd\nclass TerminalEnvironmentProvider: pass", "waiting-source"),
                (True, provider, "PINNED-READY")):
            with self.subTest(expected=expected), patch.object(watch, "api", return_value=pr), \
                    patch.object(watch, "contains", return_value=included) as ancestry, \
                    patch.object(watch, "source", return_value=text) as source:
                self.assertEqual(watch.detect("hermes-cua-version", self.hermes_lock()), expected)
                ancestry.assert_called_once_with("NousResearch/hermes-agent", watch.HERMES_CUA_FIX, "hermes-pin")
                if included:
                    source.assert_called_once_with("NousResearch/hermes-agent", "agent/terminal_env_provider.py", "hermes-pin")
                else:
                    source.assert_not_called()
        with patch.object(watch, "api", return_value={"merged": True, "merge_commit_sha": "other"}):
            with self.assertRaises(ValueError):
                watch.detect("hermes-cua-version", self.hermes_lock())

    def test_hermes_lifecycle_does_not_complete_an_unmerged_feature(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(watch, "ROOT", Path(directory)):
            self.assertEqual(watch.inspect("hermes-cua-version", self.hermes_lock()), "waiting-integration")
            gate = Path(directory) / watch.HERMES_CUA_GATE
            gate.parent.mkdir(parents=True)
            gate.write_text(watch.HERMES_CUA_VERSION_MARKER)
            with patch.object(watch, "api", side_effect=ValueError("offline")):
                self.assertTrue(watch.inspect("hermes-cua-version", self.hermes_lock()).startswith("unavailable"))
            gate.write_text("")
            self.assertTrue(watch.inspect("hermes-cua-version", self.hermes_lock()).startswith("unavailable"))
            gate.write_text('lib.hasInfix "supports_streams" provider\nlib.hasInfix "default_cwd" provider\n'
                            'lib.versionAtLeast runtime.version "0.7.0"\nlib.versionOlder runtime.version "0.8"')
            self.assertEqual(watch.inspect("hermes-cua-version", self.hermes_lock()), "completed")

    def test_hermes_cleanup_applies_once_and_rejects_drift(self):
        import shutil
        root = Path(__file__).resolve().parents[2]
        recipe = root / ".github/upstream/cleanup/hermes-cua-version.patch"
        paths = [line.split()[2][2:] for line in recipe.read_text().splitlines() if line.startswith("diff --git ")]
        self.assertTrue(paths and all(path.startswith("modules/") for path in paths))
        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory)
            for relative in paths:
                target = candidate / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(root / relative, target)
            gate = candidate / watch.HERMES_CUA_GATE
            # Candidate CI also runs after retirement; reconstruct its exact
            # pre-cleanup baseline before exercising application and drift.
            if watch.HERMES_CUA_VERSION_MARKER not in gate.read_text():
                subprocess.run(["git", "apply", "--reverse", str(recipe)], cwd=candidate, check=True, capture_output=True)
            subprocess.run(["git", "apply", "--check", str(recipe)], cwd=candidate, check=True, capture_output=True)
            original = gate.read_text()
            gate.write_text(original.replace('version "0.22.3"', 'version "0.22.4"'))
            self.assertNotEqual(subprocess.run(["git", "apply", "--check", str(recipe)], cwd=candidate, capture_output=True).returncode, 0)
            gate.write_text(original)
            subprocess.run(["git", "apply", str(recipe)], cwd=candidate, check=True, capture_output=True)
            self.assertNotEqual(subprocess.run(["git", "apply", "--check", str(recipe)], cwd=candidate, capture_output=True).returncode, 0)
            with patch.object(watch, "ROOT", candidate):
                self.assertEqual(watch.inspect("hermes-cua-version", self.hermes_lock()), "completed")
            entry = (root / "modules/aspects/services/hermes-cua/entrypoint.py").read_text()
            self.assertIn("return False", entry)
            self.assertIn("refusing local fallback", entry)

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

    def test_t3code_version_detection_survives_the_package_split(self):
        missing = subprocess.CalledProcessError(1, ["gh"], stderr="HTTP 404: Not Found")
        with patch.object(watch, "source", side_effect=[missing,
                          'version = "0.1.0"; tag = "v${finalAttrs.version}";']) as source:
            self.assertEqual(watch.t3code_stable_tag("pin"), "v0.1.0")
            self.assertEqual(source.call_args.args[1], "pkgs/by-name/t3/t3code-cli/unwrapped.nix")
        unavailable = subprocess.CalledProcessError(1, ["gh"], stderr="HTTP 503")
        with patch.object(watch, "source", side_effect=unavailable) as source:
            with self.assertRaises(subprocess.CalledProcessError):
                watch.t3code_stable_tag("pin")
            self.assertEqual(source.call_count, 1)

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
                gate.assert_called_once_with(LOCK, minimum_version=watch.T3CODE_STABLE_MIN_VERSION)
        with patch.object(watch, "t3code_nightly_v2_status", side_effect=ValueError("boom")):
            with self.assertRaises(ValueError):
                watch.detect("t3code-stable010", LOCK)

    def test_t3code_bridge_cleanup_cannot_downgrade_the_installed_release(self):
        def api(endpoint):
            if endpoint.endswith("/commits/nixos-unstable"):
                return {"sha": "a" * 40}
            tag = endpoint.rsplit("/", 1)[-1] if "/releases/tags/" in endpoint else "v0.1.1"
            return {"tag_name": tag, "draft": False, "prerelease": False}
        for channel, pinned, expected in (
                ("v0.1.0", "v0.1.0", "waiting-unstable"),
                ("v0.1.1", "v0.1.0", "merged-not-pinned"),
                ("v0.1.1", "v0.1.1", "PINNED-READY"),
                ("v0.1.10", "v0.1.10", "PINNED-READY")):
            with self.subTest(channel=channel, pinned=pinned), \
                    patch.object(watch, "api", side_effect=api), \
                    patch.object(watch, "contains", return_value=True), \
                    patch.object(watch, "t3code_stable_tag", side_effect=[channel, pinned]):
                self.assertEqual(watch.detect("t3code-stable010", LOCK), expected)

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

