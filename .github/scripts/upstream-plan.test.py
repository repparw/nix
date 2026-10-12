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
        self.module.write_text("services.authelia.instances.main.package = pkgs.authelia;\n")
        self.assertEqual(self.evaluate()["action"], "normal")

    def test_cleanup_narrow_idempotence_fail_closed(self):
        planner.remove_authelia(self.module)
        content = self.module.read_text()
        self.assertNotIn("autheliaPackage", content)
        self.assertIn("services.authelia.instances.main = {", content)
        with self.assertRaises(ValueError):
            planner.remove_authelia(self.module)

    def test_wrong_cleanup_shape_no_write(self):
        before = self.module.read_text().replace("pkgs.authelia;", "pkgs.not-authelia;")
        self.module.write_text(before)
        with self.assertRaises(ValueError):
            planner.remove_authelia(self.module)
        self.assertEqual(before, self.module.read_text())

    def test_registry_explicitly_limits_publication(self):
        self.assertEqual([k for k,v in self.registry.items() if v["mode"] == "atomic"],
                         ["authelia-pnpm-hash"])
        self.assertEqual(self.registry["moonshine-pr227"]["mode"], "host-owned")
        self.assertEqual(self.registry["nautilus-module"]["mode"], "notify-only")
        for name, spec in self.registry.items():
            if spec["mode"] == "post-lock":
                self.assertTrue((ROOT / ".github/upstream/cleanup" / spec["cleanup"]).exists(), name)


if __name__ == "__main__":
    unittest.main()
