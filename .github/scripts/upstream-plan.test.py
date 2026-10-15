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

    def evaluate(self, old="old", new="new", ancestry=None, channel=None):
        if ancestry is None:
            ancestry = lambda commit, rev: rev in ("new", "channel")
        if channel is None:
            channel = lambda url: {"sha": "channel"}
        return planner.plan(lock(old), lock(new), self.registry, self.module, ancestry, channel)

    def test_normal_when_nixpkgs_pin_unchanged(self):
        self.assertEqual(self.evaluate(old="old", new="old")["action"], "normal")

    def test_normal_when_fix_not_in_candidate(self):
        self.assertEqual(self.evaluate(ancestry=lambda *_: False)["action"], "normal")

    def test_ready_only_with_pin_and_channel(self):
        self.assertEqual(self.evaluate()["action"], "atomic-review")
        result = self.evaluate(ancestry=lambda _c, rev: rev == "new")
        self.assertEqual(result["action"], "blocked")
        self.assertIn("nixos-unstable", result["reason"])

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
