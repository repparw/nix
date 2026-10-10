#!/usr/bin/env python3
"""Inspect upstream fixes in the checked-out pins without publishing changes."""
import argparse
import base64
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PR_WAITS = {
    "authelia-pnpm-hash": ("NixOS/nixpkgs", 572207, "nixpkgs"),
    "t3code-connect": ("NixOS/nixpkgs", 555921, "nixpkgs"),
    "t3code-split": ("NixOS/nixpkgs", 555814, "nixpkgs"),
    "tasks-org": ("NixOS/nixpkgs", 518221, "nixpkgs"),
    "nautilus-module": ("NixOS/nixpkgs", 319535, "nixpkgs"),
    "t3code-server": ("nix-community/home-manager", 9695, "home-manager"),
    "cliamp-hm-module": ("nix-community/home-manager", 9842, "home-manager"),
}
WORKAROUNDS = {
    "authelia-pnpm-hash": ("modules/_services/authelia.nix", "autheliaPackage"),
    "t3code-connect": ("modules/aspects/ai/t3code-connect.nix", None),
    "t3code-split": ("modules/aspects/ai/t3code-split.nix", None),
    "tasks-org": ("modules/aspects/gui/apps.nix", "tasksOrgPackage"),
    "t3code-server": ("modules/aspects/ai/t3code.nix", "services.t3code-web"),
    "cliamp-hm-module": ("modules/aspects/cliamp.nix", "hmCliampModule"),
    "cliamp-attach": ("modules/aspects/cliamp.nix", 'owner = "ryanrpj"'),
    "qbittorrent": ("modules/aspects/services/arr.nix", "qbittorrent-nox.overrideAttrs"),
    "wpaperd-fix": ("modules/aspects/gui/wpaperd-output-removal-race.patch", None),
    "voxtype-graphical": ("modules/aspects/ai/voxtype-graphical-workaround.nix", None),
    "gamescope-vkroots": ("modules/aspects/streaming.nix", "queueInfo.flags) { VkDeviceQueueInfo2"),
}


def api(endpoint):
    result = subprocess.run(["gh", "api", endpoint], capture_output=True, text=True, timeout=45, check=True)
    return json.loads(result.stdout)


def source(repository, path, revision):
    data = api(f"repos/{repository}/contents/{path}?ref={revision}")
    return base64.b64decode(data["content"], validate=False).decode()


def contains(repository, merge, revision):
    comparison = api(f"repos/{repository}/compare/{merge}...{revision}")
    return comparison.get("status") in ("ahead", "identical") and comparison["merge_base_commit"]["sha"] == merge


def pin(lock, input_name):
    node = lock["nodes"]["root"]["inputs"][input_name]
    # Root inputs are direct references. Reject unsupported lock shapes.
    return lock["nodes"][node]["locked"]["rev"]


def source_ref(text):
    rev = re.search(r'\brev\s*=\s*"([^"]+)";', text)
    if rev:
        return rev.group(1)
    version = re.search(r'\bversion\s*=\s*"([^"]+)";', text)
    tag = re.search(r'\btag\s*=\s*"([^"]+)";', text)
    if version and re.search(r"\btag\s*=\s*finalAttrs.version\s*;", text):
        return version.group(1)
    if not version or not tag:
        raise ValueError("package source ref is not a literal revision or version tag")
    return tag.group(1).replace("${finalAttrs.version}", version.group(1)).replace("${version}", version.group(1))


def package_contains(package, repository, merge, revision):
    package_text = source("NixOS/nixpkgs", f"pkgs/by-name/{package[:2]}/{package}/package.nix", revision)
    return contains(repository, merge, source_ref(package_text))


def flagged_queues_fixed(header):
    # Both lookup sites must select GetDeviceQueue2 using that queue's flags,
    # while preserving the legacy call for unflagged queues. An unrelated
    # declaration of GetDeviceQueue2 is insufficient.
    bodies = re.findall(r"if\s*\(\s*queueInfo.flags\s*\)\s*\{(.*?)\}\s*else\s*(?:\{)?(.*?GetDeviceQueue\([^;]*;)", header, re.S)
    return len(bodies) >= 2 and all("VkDeviceQueueInfo2" in body and "GetDeviceQueue2(" in body for body, _ in bodies)


def gamescope_fixed():
    # Run only unpack + package patches. Use raw pkgs.gamescope, without the
    # repository's gamescopeHdr postPatch. No GPU, activation, or lock mutation.
    expression = '''let f = builtins.getFlake (builtins.getEnv "UPSTREAM_WATCH_ROOT");
    g = f.nixosConfigurations.alpha.pkgs.gamescope.override { enableWsi = true; };
    in g.overrideAttrs (_: { pname = "gamescope-upstream-source-check";
      configurePhase = "true"; buildPhase = "true"; doCheck = false;
      installPhase = "mkdir -p $out; cp subprojects/vkroots/vkroots.h $out/vkroots.h";
      fixupPhase = "true"; })'''
    import os
    result = subprocess.run(["nix", "build", "--impure", "--no-link", "--no-write-lock-file", "--print-out-paths", "--expr", expression], env={**os.environ, "UPSTREAM_WATCH_ROOT": str(ROOT)}, capture_output=True, text=True, timeout=900, check=True)
    return flagged_queues_fixed((Path(result.stdout.strip()) / "vkroots.h").read_text())


def detect(name, lock):
    if name in PR_WAITS:
        repo, number, input_name = PR_WAITS[name]
        pr = api(f"repos/{repo}/pulls/{number}")
        if not pr.get("merged"):
            return "waiting-upstream"
        return "PINNED-READY" if contains(repo, pr["merge_commit_sha"], pin(lock, input_name)) else "merged-not-pinned"
    revision = pin(lock, "nixpkgs")
    if name in ("qbittorrent", "moonshine-pr227"):
        repo, number, package = {"qbittorrent": ("qbittorrent/qBittorrent", 24055, "qbittorrent"), "moonshine-pr227": ("hgaiser/moonshine", 227, "moonshine")}[name]
        pr = api(f"repos/{repo}/pulls/{number}")
        if not pr.get("merged"):
            return "waiting-upstream"
        return "PINNED-READY" if package_contains(package, repo, pr["merge_commit_sha"], revision) else "merged-not-pinned"
    if name == "wpaperd-fix":
        fixed = package_contains("wpaperd", "danyspin97/wpaperd", "442b962df717dfb6e3d86a3a4bfd1111882323b8", revision)
    elif name == "cliamp-attach":
        package_text = source("NixOS/nixpkgs", "pkgs/by-name/cl/cliamp/package.nix", revision)
        commands = source("bjarneo/cliamp", "commands.go", source_ref(package_text))
        fixed = all(re.search(rf'\b{command}Command\s*\(|"{command}"', commands) for command in ("attach", "quit"))
    elif name == "voxtype-graphical":
        # The override is a Home Manager user unit, not a NixOS system unit.
        module = source("nix-community/home-manager", "modules/services/voxtype.nix", pin(lock, "home-manager"))
        fixed = all(re.search(rf"\b{option}\s*=\s*\[\s*\"graphical-session.target\"", module) for option in ("PartOf", "After", "WantedBy"))
    elif name == "gamescope-vkroots":
        fixed = gamescope_fixed()
    elif name == "sonarr-jellyfin":
        return "host-owned: inspect running Sonarr on Alpha"
    else:
        raise ValueError(f"unknown watcher {name}")
    return "PINNED-READY" if fixed else "merged-not-pinned"


def inspect(name, lock):
    try:
        if name in WORKAROUNDS:
            relative, marker = WORKAROUNDS[name]
            path = ROOT / relative
            if not path.exists() or marker is not None and marker not in path.read_text():
                return "completed"
        return detect(name, lock)
    except (subprocess.SubprocessError, OSError, ValueError, KeyError, TypeError) as error:
        # Do not echo raw transport output, which can contain credentials.
        return f"unavailable ({type(error).__name__})"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    lock = json.loads((ROOT / "flake.lock").read_text())
    names = [*PR_WAITS, "qbittorrent", "wpaperd-fix", "voxtype-graphical", "cliamp-attach", "gamescope-vkroots", "moonshine-pr227", "sonarr-jellyfin"]
    results = {name: inspect(name, lock) for name in names}
    if args.json:
        print(json.dumps(results, sort_keys=True))
    else:
        for name, status in results.items():
            print(f"{name}: {status}")


if __name__ == "__main__":
    main()
