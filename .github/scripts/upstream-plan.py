#!/usr/bin/env python3
"""Pre-publication watcher planner. No writes or cleanup publication in plan mode.

Reads candidate locks before fast-forward. Apply-coupled workarounds must
be cleaned up in the same validated lock candidate.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / ".github/upstream/watchers.json"

# Apply-coupled workarounds break the moment the candidate pin carries their
# fix (or any context-shifting package bump): their cleanup must ride the lock
# candidate instead of racing the post-lock sweep. The probe attribute builds
# each fleet package with stubbed compile phases, which still executes the
# apply-coupled logic: fetchpatch, substituteInPlace, and patch application.
APPLY_COUPLED_PROBES = {
    "qbittorrent": "nixosConfigurations.alpha.config.containers.qbittorrent.config.services.qbittorrent.package",
    "gamescope-vkroots": "nixosConfigurations.alpha.pkgs.gamescope",
    "moonshine-pr227": "nixosConfigurations.alpha.pkgs.moonshine-pr227",
}


def pin(lock, name):
    node = lock["nodes"]["root"]["inputs"][name]
    return lock["nodes"][node]["locked"]["rev"]



def nix_probe_expression(attribute):
    # This probe checks source compatibility; binary checks belong to full builds.
    return (
        'let f = builtins.getFlake (builtins.getEnv "UPSTREAM_WATCH_ROOT"); '
        f'in (f.{attribute}).overrideAttrs (_: {{ '
        'phases = [ "unpackPhase" "patchPhase" "installPhase" ]; '
        'installPhase = "mkdir -p $out; touch $out/probed"; '
        '})'
    )


def nix_build_ok(attribute):
    expression = nix_probe_expression(attribute)
    result = subprocess.run(
        ["nix", "build", "--impure", "--no-link", "--no-write-lock-file",
         "--print-out-paths", "--expr", expression],
        env={**os.environ, "UPSTREAM_WATCH_ROOT": str(ROOT)},
        capture_output=True, text=True, timeout=1800,
    )
    return result.returncode == 0, (result.stderr or "")[-300:]

def plan(old, candidate, registry, readiness_fn=None, probe_fn=None,
         build_probe=True):
    """Divert lock publication when an apply-coupled cleanup must ride it.

    readiness_fn(name) -> status string, evaluated against the candidate tree.
    probe_fn(attribute) -> (ok, detail), building the patched fleet package
    with stubbed compile phases. With build_probe=False the probe is skipped
    (fixture mode).
    """
    probe_fn = probe_fn or nix_build_ok

    for name, spec in registry.items():
        if spec["mode"] not in ("post-lock", "host-owned", "notify-only", "completed"):
            raise ValueError(f"unsupported watcher mode: {name}")

    # Apply-coupled watchers: their cleanup rides this lock candidate.
    pin_moved = pin(old, "nixpkgs") != pin(candidate, "nixpkgs")
    atomic_names = []
    apply_names = [name for name, spec in registry.items() if spec.get("coupling") == "apply"]
    # No apply-coupled nixpkgs workaround can become newly ready if the pin
    # did not change. Inspect exactly the relevant watchers once per candidate.
    if pin_moved and readiness_fn is None:
        statuses = _candidate_readiness(apply_names)
        readiness_fn = statuses.__getitem__
    for name in apply_names:
        spec = registry[name]
        if spec["mode"] != "post-lock":
            raise ValueError(f"{name}: apply coupling requires post-lock mode")
        if not pin_moved:
            continue
        status = readiness_fn(name)
        if isinstance(status, str) and status.startswith("unavailable"):
            return {"action": "blocked", "atomic": [],
                    "reason": f"{name} readiness unavailable: {status}"}
        if status == "completed":
            continue  # the workaround is already gone from the candidate tree
        if status == "PINNED-READY":
            atomic_names.append(name)
        elif pin_moved and build_probe:
            ok, detail = probe_fn(APPLY_COUPLED_PROBES[name])
            if not ok:
                return {"action": "blocked", "atomic": [],
                        "reason": f"{name} workaround no longer applies to the candidate pin: {detail}"}

    if atomic_names:
        # The combined candidate merge-automates under the #265 policy:
        # GitHub merges exactly when the required checks pass and the
        # branch is strict up-to-date with main. The registry checker is
        # the sole landing decision; the cleanup is declarative.
        return {"action": "atomic", "atomic": sorted(atomic_names),
                "automerge": True,
                "reason": "candidate requires coupled lock and cleanup publication"}
    return {"action": "normal", "atomic": [], "reason": "no atomic cleanup required"}


def _candidate_readiness(names):
    # Run only the apply-coupled detectors against this candidate's lock.
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "candidate-readiness", ROOT / ".github/scripts/upstream-readiness.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    lock = json.loads((ROOT / "flake.lock").read_text())
    return {name: module.inspect(name, lock) for name in names}

def apply_recipe(name, spec):
    """Apply an apply-coupled cleanup recipe to the workspace tree."""
    patch = ROOT / ".github/upstream/cleanup" / spec["cleanup"]
    if patch.parent != ROOT / ".github/upstream/cleanup" or patch.suffix != ".patch":
        raise ValueError("invalid cleanup path")
    run_apply = subprocess.run(["git", "apply", "--check", str(patch)],
                               capture_output=True, text=True, cwd=ROOT)
    if run_apply.returncode != 0:
        raise ValueError(f"{name} cleanup does not apply to the candidate: {run_apply.stderr[-300:]}")
    subprocess.run(["git", "apply", str(patch)], check=True, cwd=ROOT)



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    planning = sub.add_parser("plan")
    planning.add_argument("--old", type=Path, required=True)
    planning.add_argument("--candidate", type=Path, required=True)

    planning.add_argument("--registry", type=Path, default=REGISTRY)
    cleaning = sub.add_parser("apply")
    cleaning.add_argument("--id", required=True)

    cleaning.add_argument("--registry", type=Path, default=REGISTRY)
    args = parser.parse_args()
    if args.command == "apply":
        registry = json.loads(args.registry.read_text())

        spec = registry.get(args.id, {})
        if spec.get("coupling") != "apply":
            raise SystemExit(f"{args.id} is not an apply-coupled cleanup")
        apply_recipe(args.id, spec)
        return
    result = plan(json.loads(args.old.read_text()),
                  json.loads(args.candidate.read_text()),
                  json.loads(args.registry.read_text()))
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
