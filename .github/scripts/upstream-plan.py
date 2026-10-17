#!/usr/bin/env python3
"""Pre-publication watcher planner. No writes or cleanup publication in plan mode.

Reads the candidate lock before the automated fast-forward. Only explicitly
atomic entries can divert publication. Other watchers retain the separate,
read-only post-main readiness sweep until the pilot has completed.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / ".github/upstream/watchers.json"
AUTHELIA_MODULE = ROOT / "modules/_services/authelia.nix"
AUTHELIA_MARKER = "autheliaPackage"
AUTHELIA_STALE_HASH = "sha256-YUInqRclRdnMzxfJKuVdXwKaRzJd9sFu16dxCAgVJI8"

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

# Keep this exact. A changed override must be reviewed instead of rewritten by
# automation, even if the line count and surrounding markers still match.
AUTHELIA_OVERRIDE = "  # pnpm 12.9 changed the dependency output: nixpkgs issue #571789.\n  # Only repair the known aarch64 hash; a corrected upstream hash retires this.\n  autheliaPackage =\n    if\n      pkgs.stdenv.hostPlatform.system == \"aarch64-linux\"\n      && pkgs.authelia.version == \"4.39.28\"\n      && pkgs.authelia.web.pnpmDeps.outputHash == \"sha256-B/Au9YICuRM6+J4DojFbXf2IEWC+j1jRsU68nn08Puk=\"\n    then\n      pkgs.authelia.override {\n        authelia-web = pkgs.authelia.web.overrideAttrs (old: {\n          pnpmDeps = old.pnpmDeps.overrideAttrs {\n            outputHash = \"sha256-YUInqRclRdnMzxfJKuVdXwKaRzJd9sFu16dxCAgVJI8=\";\n          };\n        });\n      }\n    else\n      pkgs.authelia;\n"
AUTHELIA_CONSUMER = "        package = autheliaPackage;"
AUTHELIA_REPLACEMENT = "        package = pkgs.authelia;"


def pin(lock, name):
    node = lock["nodes"]["root"]["inputs"][name]
    return lock["nodes"][node]["locked"]["rev"]


def api(endpoint):
    result = subprocess.run(["gh", "api", endpoint], check=True,
                            capture_output=True, text=True, timeout=45)
    return json.loads(result.stdout)


def contains(commit, revision):
    data = api(f"repos/NixOS/nixpkgs/compare/{commit}...{revision}")
    if not isinstance(data, dict) or data.get("status") not in (
            "ahead", "behind", "identical", "diverged"):
        raise ValueError("invalid ancestry comparison")
    base = data.get("merge_base_commit")
    if not isinstance(base, dict) or not isinstance(base.get("sha"), str):
        raise ValueError("invalid comparison merge base")
    return data["status"] in ("ahead", "identical") and base["sha"] == commit


def nix_probe_expression(attribute):
    # Shared verbatim by the compatibility build and real Nix eval smoke tests.
    return (
        'let f = builtins.getFlake (builtins.getEnv "UPSTREAM_WATCH_ROOT"); '
        f'in (f.{attribute}).overrideAttrs (_: {{ '
        'configurePhase = "true"; buildPhase = "true"; '
        'doCheck = false; checkPhase = "true"; '
        'installPhase = "mkdir -p $out; touch $out/probed"; '
        'fixupPhase = "true"; })'
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

def plan(old, candidate, registry, module, contains_fn=contains, api_fn=api,
         readiness_fn=None, probe_fn=None, build_probe=True):
    """Divert lock publication when an apply-coupled cleanup must ride it.

    readiness_fn(name) -> status string, evaluated against the candidate tree.
    probe_fn(attribute) -> (ok, detail), building the patched fleet package
    with stubbed compile phases. With build_probe=False the probe is skipped
    (fixture mode).
    """
    probe_fn = probe_fn or nix_build_ok
    actions = []
    for name, spec in registry.items():
        if spec["mode"] == "atomic":
            actions.append(name)
        elif spec["mode"] not in ("post-lock", "host-owned", "notify-only", "completed"):
            raise ValueError(f"unsupported watcher mode: {name}")
    if actions != ["authelia-pnpm-hash"]:
        # An additional atomic publisher needs its own safe cleanup handler.
        raise ValueError("unexpected atomic watcher")
    item = registry["authelia-pnpm-hash"]
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
    if not module.exists():
        return {"action": "blocked", "atomic": [], "reason": "Authelia module missing"}
    content = module.read_text()
    if AUTHELIA_MARKER not in content:
        # Authelia has already been cleaned up on main. That does NOT make
        # the independent apply-coupled cleanups safe to publish separately.
        leftover = (
            AUTHELIA_STALE_HASH,
            "pnpmDeps = old.pnpmDeps.overrideAttrs",
            "authelia-web = pkgs.authelia.web.overrideAttrs",
        )
        if any(token in content for token in leftover):
            return {"action": "blocked", "atomic": [], "reason": "unrecognized Authelia override survives"}
        if "services.authelia.instances.main = {" not in content:
            return {"action": "blocked", "atomic": [], "reason": "Authelia service declaration missing"}
    else:
        if content.count(AUTHELIA_OVERRIDE) != 1 or content.count(AUTHELIA_CONSUMER) != 1:
            return {"action": "blocked", "atomic": [], "reason": "Authelia override shape changed"}
        try:
            fixed = contains_fn(item["fix_commit"], pin(candidate, "nixpkgs"))
        except (OSError, ValueError, subprocess.SubprocessError, KeyError, TypeError):
            return {"action": "blocked", "atomic": [], "reason": "candidate pin ancestry unavailable"}
        if fixed:
            try:
                channel = api_fn("repos/NixOS/nixpkgs/commits/nixos-unstable")
                available = contains_fn(item["fix_commit"], channel["sha"])
            except (OSError, ValueError, subprocess.SubprocessError, KeyError, TypeError):
                return {"action": "blocked", "atomic": [], "reason": "channel ancestry unavailable"}
            if not available:
                return {"action": "blocked", "atomic": [],
                        "reason": "candidate includes fix before nixos-unstable; requires manual review"}
            atomic_names.append("authelia-pnpm-hash")
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


def remove_authelia(module):
    """Remove only the byte-for-byte known override, leaving explicit package selection."""
    content = module.read_text()
    if content.count(AUTHELIA_OVERRIDE) != 1 or content.count(AUTHELIA_CONSUMER) != 1:
        raise ValueError("Authelia override differs from reviewed fixture")
    result = content.replace(AUTHELIA_OVERRIDE, "", 1).replace(
        AUTHELIA_CONSUMER, AUTHELIA_REPLACEMENT, 1)
    if AUTHELIA_STALE_HASH in result or AUTHELIA_MARKER in result:
        raise ValueError("Authelia override survived cleanup")
    module.write_text(result)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    planning = sub.add_parser("plan")
    planning.add_argument("--old", type=Path, required=True)
    planning.add_argument("--candidate", type=Path, required=True)
    planning.add_argument("--module", type=Path, default=AUTHELIA_MODULE)
    planning.add_argument("--registry", type=Path, default=REGISTRY)
    cleaning = sub.add_parser("apply")
    cleaning.add_argument("--id", required=True)
    cleaning.add_argument("--module", type=Path, default=AUTHELIA_MODULE)
    cleaning.add_argument("--registry", type=Path, default=REGISTRY)
    args = parser.parse_args()
    if args.command == "apply":
        registry = json.loads(args.registry.read_text())
        if args.id == "authelia-pnpm-hash":
            remove_authelia(args.module)
            return
        spec = registry.get(args.id, {})
        if spec.get("coupling") != "apply":
            raise SystemExit(f"{args.id} is not an apply-coupled cleanup")
        apply_recipe(args.id, spec)
        return
    result = plan(json.loads(args.old.read_text()),
                  json.loads(args.candidate.read_text()),
                  json.loads(args.registry.read_text()), args.module)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
