#!/usr/bin/env python3
"""Focused tests for lock candidate atomic plan and fail-closed cleanup."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("upstream_plan", ROOT / ".github/scripts/upstream-plan.py")
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)


def lock(pin):
    return {"nodes": {"root": {"inputs": {"nixpkgs": "n", "home-manager": "h"}},
                      "n": {"locked": {"rev": pin}},
                      "h": {"locked": {"rev": "home-manager-pin"}}}}


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.module = Path(self.temp.name) / "authelia.nix"
        self.module.write_text((ROOT / ".github/upstream/fixtures/authelia-before.nix.txt").read_text())
        self.registry = json.loads((ROOT / ".github/upstream/watchers.json").read_text())

    def tearDown(self):
        self.temp.cleanup()

    def evaluate(self, old="old", new="new", ancestry=None, channel=None,
                 readiness=None, probe=None, build_probe=True):
        if ancestry is None:
            ancestry = lambda commit, rev: rev in ("new", "channel")
        if channel is None:
            channel = lambda url: {"sha": "channel"}
        if readiness is None:
            readiness = lambda name: "waiting-upstream"
        if probe is None:
            probe = lambda attribute: (True, "")
        return planner.plan(lock(old), lock(new), self.registry, self.module,
                            ancestry, channel, readiness_fn=readiness,
                            probe_fn=probe, build_probe=build_probe)

    def test_normal_when_nixpkgs_pin_unchanged(self):
        self.assertEqual(self.evaluate(old="old", new="old")["action"], "normal")

    def test_normal_when_fix_not_in_candidate(self):
        self.assertEqual(self.evaluate(ancestry=lambda *_: False)["action"], "normal")

    def test_ready_only_with_pin_and_channel(self):
        self.assertEqual(self.evaluate()["action"], "atomic-review")
        result = self.evaluate(ancestry=lambda _c, rev: rev == "new")
        self.assertEqual(result["action"], "blocked")
        self.assertIn("nixos-unstable", result["reason"])

    def test_apply_coupled_ready_diverts_the_lock(self):
        def readiness(name):
            return "PINNED-READY" if name == "qbittorrent" else "waiting-upstream"
        result = self.evaluate(readiness=readiness)
        self.assertEqual(result["action"], "atomic-review")
        self.assertIn("qbittorrent", result["atomic"])
        self.assertNotIn("gamescope-vkroots", result["atomic"])

    def test_apply_coupled_unavailable_blocks_the_lock(self):
        result = self.evaluate(readiness=lambda name: "unavailable (CalledProcessError)")
        self.assertEqual(result["action"], "blocked")
        self.assertIn("unavailable", result["reason"])

    def test_apply_coupled_probe_failure_blocks_the_lock(self):
        # Not ready, but the pin moved and the workaround no longer applies:
        # publishing the lock would break the fleet's build.
        result = self.evaluate(probe=lambda attribute: (False, "patch does not apply"))
        self.assertEqual(result["action"], "blocked")
        self.assertIn("no longer applies", result["reason"])

    def test_apply_coupled_probe_pass_keeps_normal_publication(self):
        result = self.evaluate(ancestry=lambda *_: False, probe=lambda attribute: (True, ""))
        self.assertEqual(result["action"], "normal")

    def test_pin_unchanged_never_probes(self):
        def explode(attribute):
            raise AssertionError("compatibility probe must run only when the pin moved")
        self.assertEqual(self.evaluate(old="old", new="old", probe=explode)["action"], "normal")

    def test_completed_apply_coupled_skips_probe_and_divert(self):
        result = self.evaluate(ancestry=lambda *_: False,
                               readiness=lambda name: "completed",
                               probe=lambda attribute: (False, "must not run"))
        self.assertEqual(result["action"], "normal")

    def test_apply_coupled_probe_runs_only_for_the_flagged_three(self):
        seen = []
        self.evaluate(probe=lambda attribute: (seen.append(attribute), (True, ""))[1])
        self.assertEqual(sorted(seen), sorted(["nixosConfigurations.alpha.config.containers.qbittorrent.config.services.qbittorrent.package",
                                               "nixosConfigurations.alpha.pkgs.gamescope",
                                               "nixosConfigurations.alpha.pkgs.moonshine-pr227"]))

    def test_completed_authelia_does_not_discard_ready_cleanup(self):
        planner.remove_authelia(self.module)
        result = self.evaluate(readiness=lambda name: "PINNED-READY" if name == "qbittorrent"
                               else "waiting-upstream",
                               ancestry=lambda *_: False)
        self.assertEqual(result["action"], "atomic-review")
        self.assertEqual(result["atomic"], ["qbittorrent"])

    def test_completed_authelia_can_batch_all_three(self):
        planner.remove_authelia(self.module)
        result = self.evaluate(readiness=lambda _: "PINNED-READY")
        self.assertEqual(result["atomic"],
                         ["gamescope-vkroots", "moonshine-pr227", "qbittorrent"])

    def test_unchanged_pin_skips_readiness(self):
        def explode(_):
            raise AssertionError("readiness must not run without a nixpkgs change")
        result = self.evaluate(old="new", new="new", readiness=explode,
                               ancestry=lambda *_: False)
        self.assertEqual(result["action"], "normal")

    def test_default_readiness_runs_once_for_three_watchers(self):
        selected = []
        def statuses(names):
            selected.append(names)
            return {name: "waiting-upstream" for name in names}
        with patch.object(planner, "_candidate_readiness", side_effect=statuses):
            planner.plan(lock("old"), lock("new"), self.registry, self.module,
                         contains_fn=lambda *_: False,
                         probe_fn=lambda _: (True, ""))
        self.assertEqual(selected, [["qbittorrent", "gamescope-vkroots",
                                     "moonshine-pr227"]])

    def test_real_probe_constructs_nix_expression_and_preserves_patch_phase(self):
        class Done:
            returncode = 0
            stderr = ""
        with patch.object(planner.subprocess, "run", return_value=Done()) as run:
            ok, _ = planner.nix_build_ok(planner.APPLY_COUPLED_PROBES["qbittorrent"])
        self.assertTrue(ok)
        args = run.call_args.args[0]
        self.assertIn("--expr", args)
        self.assertIn("--impure", args)
        expression = args[args.index("--expr") + 1]
        self.assertIn("containers.qbittorrent.config.services.qbittorrent.package", expression)
        self.assertIn("overrideAttrs", expression)
        self.assertNotIn("patchPhase =", expression)
        self.assertEqual(run.call_args.kwargs["env"]["UPSTREAM_WATCH_ROOT"],
                         str(planner.ROOT))

    def test_unknown_ancestry_must_not_auto_publish(self):
        def unavailable(*_):
            raise subprocess.CalledProcessError(1, "gh")
        self.assertEqual(self.evaluate(ancestry=unavailable)["action"], "blocked")
        self.assertEqual(self.evaluate(channel=unavailable)["action"], "blocked")

    def test_completed_workaround_never_diverts(self):
        before = self.module.read_text()
        self.module.write_text(before.replace(planner.AUTHELIA_OVERRIDE, "").replace(
            planner.AUTHELIA_CONSUMER, planner.AUTHELIA_REPLACEMENT))
        self.assertEqual(self.evaluate()["action"], "normal")

    def test_cleanup_narrow_idempotence_fail_closed(self):
        planner.remove_authelia(self.module)
        content = self.module.read_text()
        self.assertNotIn("autheliaPackage", content)
        self.assertIn("services.authelia.instances.main = {", content)
        self.assertIn(planner.AUTHELIA_REPLACEMENT, content)
        with self.assertRaises(ValueError):
            planner.remove_authelia(self.module)

    def test_wrong_cleanup_shape_no_write(self):
        before = self.module.read_text().replace("pkgs.authelia;", "pkgs.not-authelia;")
        self.module.write_text(before)
        with self.assertRaises(ValueError):
            planner.remove_authelia(self.module)
        self.assertEqual(before, self.module.read_text())

    def test_renamed_override_is_never_considered_completed(self):
        original = self.module.read_text()
        self.module.write_text(original.replace("autheliaPackage", "renamedAuthelia"))
        self.assertEqual(self.evaluate()["action"], "blocked")
        self.assertIn("unrecognized", self.evaluate()["reason"])
        self.assertEqual(original.count(planner.AUTHELIA_STALE_HASH), 1)

    def test_same_length_override_mutation_is_rejected(self):
        original = self.module.read_text()
        altered = original.replace('pkgs.authelia.version == "4.39.28"',
                                   'pkgs.authelia.version == "4.39.27"')
        self.assertEqual(len(original), len(altered))
        self.module.write_text(altered)
        self.assertEqual(self.evaluate()["action"], "blocked")
        with self.assertRaises(ValueError):
            planner.remove_authelia(self.module)
        self.assertEqual(self.module.read_text(), altered)

    def test_missing_module_must_fail_closed(self):
        self.module.unlink()
        self.assertEqual(self.evaluate()["action"], "blocked")

    def test_stale_override_matters_even_if_nixpkgs_pin_unchanged(self):
        # A previously published (already-fixed) pin must not bypass cleanup
        # on the next lock update involving only unrelated inputs.
        self.assertEqual(self.evaluate(old="new", new="new")["action"], "atomic-review")

    def test_registry_ids_match_readiness_detectors(self):
        spec = importlib.util.spec_from_file_location(
            "upstream_readiness", ROOT / ".github/scripts/upstream-readiness.py")
        readiness = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(readiness)
        expected = set(readiness.PR_WAITS) | {
            "qbittorrent", "wpaperd-fix", "voxtype-graphical", "cliamp-attach",
            "gamescope-vkroots", "moonshine-pr227", "sonarr-jellyfin",
            "t3code-nightly-v2",
            "opencode-v2",
        }
        self.assertEqual(set(self.registry), expected)

    def test_registry_explicitly_limits_publication(self):
        self.assertEqual([k for k,v in self.registry.items() if v["mode"] == "atomic"],
                         ["authelia-pnpm-hash"])
        self.assertEqual(self.registry["nautilus-module"]["mode"], "notify-only")
        for name, spec in self.registry.items():
            if spec["mode"] == "post-lock":
                self.assertTrue((ROOT / ".github/upstream/cleanup" / spec["cleanup"]).exists(), name)


if __name__ == "__main__":
    unittest.main()
