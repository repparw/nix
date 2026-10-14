#!/usr/bin/env python3
"""Pre-publication watcher planner. No writes or cleanup publication in plan mode.

Reads the candidate lock before the automated fast-forward. Only explicitly
atomic entries can divert publication. Other watchers retain the separate,
read-only post-main readiness sweep until the pilot has completed.
"""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / ".github/upstream/watchers.json"
AUTHELIA_MODULE = ROOT / "modules/_services/authelia.nix"
AUTHELIA_MARKER = "autheliaPackage"
AUTHELIA_STALE_HASH = "sha256-YUInqRclRdnMzxfJKuVdXwKaRzJd9sFu16dxCAgVJI8"

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


def plan(old, candidate, registry, module, contains_fn=contains, api_fn=api):
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
    if not module.exists():
        return {"action": "blocked", "atomic": [], "reason": "Authelia module missing"}
    content = module.read_text()
    if AUTHELIA_MARKER not in content:
        # Require positive evidence for the real service declaration. A renamed
        # variable or an otherwise altered hash override cannot be assumed done.
        leftover = (
            AUTHELIA_STALE_HASH,
            "pnpmDeps = old.pnpmDeps.overrideAttrs",
            "authelia-web = pkgs.authelia.web.overrideAttrs",
        )
        if any(token in content for token in leftover):
            return {"action": "blocked", "atomic": [], "reason": "unrecognized Authelia override survives"}
        if "services.authelia.instances.main = {" not in content:
            return {"action": "blocked", "atomic": [], "reason": "Authelia service declaration missing"}
        return {"action": "normal", "atomic": [], "reason": "Authelia workaround already removed"}
    if content.count(AUTHELIA_OVERRIDE) != 1 or content.count(AUTHELIA_CONSUMER) != 1:
        return {"action": "blocked", "atomic": [], "reason": "Authelia override shape changed"}
    try:
        fixed = contains_fn(item["fix_commit"], pin(candidate, "nixpkgs"))
    except (OSError, ValueError, subprocess.SubprocessError, KeyError, TypeError):
        return {"action": "blocked", "atomic": [], "reason": "candidate pin ancestry unavailable"}
    if not fixed:
        return {"action": "normal", "atomic": [], "reason": "fix absent from candidate pin"}
    try:
        channel = api_fn("repos/NixOS/nixpkgs/commits/nixos-unstable")
        channel_rev = channel["sha"]
        available = contains_fn(item["fix_commit"], channel_rev)
    except (OSError, ValueError, subprocess.SubprocessError, KeyError, TypeError):
        return {"action": "blocked", "atomic": [], "reason": "channel ancestry unavailable"}
    if not available:
        return {"action": "blocked", "atomic": [],
                "reason": "candidate includes fix before nixos-unstable; requires manual review"}
    return {"action": "atomic-review", "atomic": ["authelia-pnpm-hash"],
            "reason": "pin contains fix, must drop incompatible override atomically"}


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
    cleaning.add_argument("--id", choices=["authelia-pnpm-hash"], required=True)
    cleaning.add_argument("--module", type=Path, default=AUTHELIA_MODULE)
    args = parser.parse_args()
    if args.command == "apply":
        remove_authelia(args.module)
        return
    result = plan(json.loads(args.old.read_text()),
                  json.loads(args.candidate.read_text()),
                  json.loads(args.registry.read_text()), args.module)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
