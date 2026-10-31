#!/usr/bin/env python3
"""Focused tests for lock candidate atomic plan and fail-closed cleanup."""
import importlib.util
import itertools
import json
import os
from pathlib import Path
import shutil
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

        self.registry = json.loads((ROOT / ".github/upstream/watchers.json").read_text())

    def evaluate(self, old="old", new="new", readiness=None, probe=None,
                 build_probe=True):
        readiness = readiness or (lambda name: "waiting-upstream")
        probe = probe or (lambda attribute: (True, ""))
        return planner.plan(lock(old), lock(new), self.registry,
                            readiness_fn=readiness, probe_fn=probe,
                            build_probe=build_probe)

    def test_normal_when_pin_unchanged(self):
        self.assertEqual(self.evaluate(old="old", new="old")["action"], "normal")

    def test_normal_when_no_cleanup_ready(self):
        self.assertEqual(self.evaluate()["action"], "normal")

    def test_legacy_atomic_watcher_is_rejected(self):
        self.registry["retired"] = {"mode": "atomic", "input": "nixpkgs"}
        with self.assertRaisesRegex(ValueError, "unsupported watcher mode"):
            self.evaluate()

    def test_apply_coupled_ready_diverts_the_lock(self):
        def readiness(name):
            return "PINNED-READY" if name == "qbittorrent" else "waiting-upstream"
        result = self.evaluate(readiness=readiness)
        self.assertEqual(result["action"], "atomic")
        self.assertTrue(result["automerge"])
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
        result = self.evaluate(probe=lambda attribute: (True, ""))
        self.assertEqual(result["action"], "normal")

    def test_pin_unchanged_never_probes(self):
        def explode(attribute):
            raise AssertionError("compatibility probe must run only when the pin moved")
        self.assertEqual(self.evaluate(old="old", new="old", probe=explode)["action"], "normal")

    def test_completed_apply_coupled_skips_probe_and_divert(self):
        result = self.evaluate(readiness=lambda name: "completed",
                               probe=lambda attribute: (False, "must not run"))
        self.assertEqual(result["action"], "normal")

    def test_apply_coupled_probe_runs_only_for_the_flagged_three(self):
        seen = []
        self.evaluate(probe=lambda attribute: (seen.append(attribute), (True, ""))[1])
        self.assertEqual(sorted(seen), sorted(["nixosConfigurations.alpha.config.containers.qbittorrent.config.services.qbittorrent.package",
                                               "nixosConfigurations.alpha.pkgs.gamescope",
                                               "nixosConfigurations.alpha.pkgs.moonshine-pr227"]))


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
            planner.plan(lock("old"), lock("new"), self.registry,
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

    @unittest.skipUnless(os.environ.get("NIX_PROBE_SMOKE") == "1",
                         "requires the CI Nix installer and flake inputs")
    def test_real_nix_probe_build_accepts_patch_without_compilation(self):
        fixture = ROOT / ".github/upstream/fixtures/probe"
        with patch.object(planner, "ROOT", fixture), patch.dict(
                os.environ, {"UPSTREAM_PROBE_REPO": str(ROOT)}):
            ok, detail = planner.nix_build_ok("valid")
        self.assertTrue(ok, detail)

    @unittest.skipUnless(os.environ.get("NIX_PROBE_SMOKE") == "1",
                         "requires the CI Nix installer and flake inputs")
    def test_real_nix_probe_build_rejects_incompatible_patch(self):
        fixture = ROOT / ".github/upstream/fixtures/probe"
        with patch.object(planner, "ROOT", fixture), patch.dict(
                os.environ, {"UPSTREAM_PROBE_REPO": str(ROOT)}):
            ok, detail = planner.nix_build_ok("incompatible")
        self.assertFalse(ok)
        self.assertIn("patch", detail.lower())

    @unittest.skipUnless(os.environ.get("NIX_PROBE_SMOKE") == "1",
                         "requires the CI Nix installer and flake inputs")
    def test_real_nix_evaluation_of_probe_attributes(self):
        # No package compilation: .drvPath forces evaluation of the exact
        # overridden derivation used by nix_build_ok for each fleet package.
        for watcher, attribute in planner.APPLY_COUPLED_PROBES.items():
            with self.subTest(watcher=watcher):
                expression = f"({planner.nix_probe_expression(attribute)}).drvPath"
                result = subprocess.run(
                    ["nix", "eval", "--impure", "--raw", "--no-write-lock-file",
                     "--expr", expression],
                    env={**os.environ, "UPSTREAM_WATCH_ROOT": str(ROOT)},
                    capture_output=True, text=True, timeout=600,
                )
                self.assertEqual(result.returncode, 0, result.stderr[-1500:])
                self.assertTrue(result.stdout.strip().endswith(".drv"),
                                result.stdout)


    def test_registry_ids_match_readiness_detectors(self):
        spec = importlib.util.spec_from_file_location(
            "upstream_readiness", ROOT / ".github/scripts/upstream-readiness.py")
        readiness = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(readiness)
        expected = set(readiness.PR_WAITS) | {
            "qbittorrent", "wpaperd-fix",
            "gamescope-vkroots", "moonshine-pr227", "sonarr-jellyfin",
            "t3code-nightly-v2",
            "t3code-stable010",
            "t3code-browser-libs",
            "opencode-v2",
            "tridactyl-reader",
            "fsr4-rdna2",
            "nodejs-security",
        }
        self.assertEqual(set(self.registry), expected)

    def test_registry_explicitly_limits_publication(self):
        self.assertFalse(any(v["mode"] == "atomic" for v in self.registry.values()))
        self.assertEqual(self.registry["nautilus-module"]["mode"], "notify-only")
        for name, spec in self.registry.items():
            if spec["mode"] == "post-lock":
                self.assertTrue((ROOT / ".github/upstream/cleanup" / spec["cleanup"]).exists(), name)

    def test_t3code_cleanups_preserve_independent_layers_in_every_order(self):
        names = ("t3code-connect", "t3code-split", "t3code-stable010")
        files = [f"modules/aspects/upstream/{name}.nix" for name in names] + [
            "modules/aspects/ai/t3code.nix", "modules/entities.nix"]
        for order in itertools.permutations(names):
            with self.subTest(order=order), tempfile.TemporaryDirectory() as directory:
                candidate = Path(directory)
                subprocess.run(["git", "init", "-q"], cwd=candidate, check=True)
                for relative in files:
                    destination = candidate / relative
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(ROOT / relative, destination)
                for name in order:
                    cleanup = ROOT / ".github/upstream/cleanup" / f"{name}.patch"
                    subprocess.run(["git", "apply", "--check", str(cleanup)], cwd=candidate, check=True)
                    subprocess.run(["git", "apply", str(cleanup)], cwd=candidate, check=True)
                    connect = (candidate / files[0]).read_text()
                    split = (candidate / files[1]).read_text()
                    self.assertIn("exec ${lib.getExe' config.programs.t3code.package \"t3code-desktop\"}", connect)
                    self.assertIn('x-scheme-handler/t3code', connect)
                    self.assertEqual('cp .env.example .env' in connect,
                                     "t3code-connect" not in order[:order.index(name) + 1])
                    self.assertEqual('t3code-server =' in split,
                                     "t3code-split" not in order[:order.index(name) + 1])
                self.assertFalse((candidate / files[2]).exists())
                self.assertNotIn("t3code-stable010", (candidate / files[4]).read_text())
                self.assertIn("pkgs.t3code-cli", split)


if __name__ == "__main__":
    unittest.main()
