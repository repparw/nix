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
    "t3code-connect": ("modules/aspects/ai/t3code-connect.nix", "cp .env.example .env"),
    "t3code-split": ("modules/aspects/ai/t3code-split.nix", "t3code-server ="),
    "tasks-org": ("modules/aspects/gui/apps.nix", "tasksOrgPackage"),
    "t3code-server": ("modules/aspects/ai/t3code.nix", "services.t3code-web"),
    "cliamp-hm-module": ("modules/aspects/cliamp.nix", "hmCliampModule"),
    "cliamp-attach": ("modules/aspects/cliamp.nix", 'owner = "ryanrpj"'),
    "qbittorrent": ("modules/aspects/services/arr.nix", "qbittorrent-nox.overrideAttrs"),
    "wpaperd-fix": ("modules/aspects/gui/wpaperd-output-removal-race.patch", None),
    "voxtype-graphical": ("modules/aspects/ai/voxtype-graphical-workaround.nix", None),
    "gamescope-vkroots": ("modules/aspects/streaming.nix", "queueInfo.flags) { VkDeviceQueueInfo2"),
    "t3code-nightly-v2": ("modules/aspects/ai/t3code-nightly.nix", None),
    "t3code-stable010": ("modules/aspects/ai/t3code-stable010.nix", None),
    "moonshine-pr227": ("modules/aspects/moonshine-pr227-test.nix", None),
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
    g = f.inputs.nixpkgs.legacyPackages.x86_64-linux.gamescope.override { enableWsi = true; };
    in g.overrideAttrs (_: { pname = "gamescope-upstream-source-check";
      configurePhase = "true"; buildPhase = "true"; doCheck = false;
      installPhase = "mkdir -p $out; cp subprojects/vkroots/vkroots.h $out/vkroots.h";
      fixupPhase = "true"; })'''
    import os
    result = subprocess.run(["nix", "build", "--impure", "--no-link", "--no-write-lock-file", "--print-out-paths", "--expr", expression], env={**os.environ, "UPSTREAM_WATCH_ROOT": str(ROOT)}, capture_output=True, text=True, timeout=900, check=True)
    return flagged_queues_fixed((Path(result.stdout.strip()) / "vkroots.h").read_text())


def unit_removed_block(application_rs):
    # Port of the watcher's awk guard: extract the brace-matched block after
    # `if id == unit_name` and require the current-state recheck inside it.
    start = application_rs.find("if id == unit_name")
    if start == -1:
        return ""
    depth = 0
    begun = False
    for index in range(application_rs.find("{", start), len(application_rs)):
        character = application_rs[index]
        if character == "{":
            depth += 1
            begun = True
        elif character == "}":
            depth -= 1
            if begun and depth == 0:
                return application_rs[start:index + 1]
    return ""


def moonshine_reload_guard(repo, revision):
    # Mirrors the watch-moonshine-pr227 source gate (issue #147): the held
    # commits fence plus a UnitRemoved handler that rechecks the current
    # application state before tearing it down. A differently-implemented
    # equivalent keeps the status at waiting-source for human review.
    package_text = source("NixOS/nixpkgs", "pkgs/by-name/mo/moonshine/package.nix", revision)
    ref = source_ref(package_text)
    require_all = (
        ("moonshine-core/src/session/compositor/mod.rs", "mod held_commits;"),
        ("moonshine-core/src/session/compositor/handlers.rs", "held_commits::hold_until_rendered"),
        ("moonshine-core/src/session/compositor/held_commits.rs", "DMA_BUF_IOCTL_EXPORT_SYNC_FILE"),
    )
    for path, marker in require_all:
        if marker not in source(repo, path, ref):
            return False
    return "current_unit_state" in unit_removed_block(source(repo, "moonshine-core/src/session/application.rs", ref))



# Alpha's temporary nightly server remains local-owned until stable v2 is
# deployed and verified. CI only checks immutable release/package evidence.
T3CODE_V2_COMMIT = "de343914273eceb852a1d1d739cd1d38df7796ee"
T3CODE_UNWRAPPED = "pkgs/by-name/t3/t3code/unwrapped.nix"


def t3code_stable_tag(package_revision):
    try:
        text = source("NixOS/nixpkgs", T3CODE_UNWRAPPED, package_revision)
    except subprocess.CalledProcessError as error:
        if "HTTP 404" not in (error.stderr or ""):
            raise
        text = source("NixOS/nixpkgs", "pkgs/by-name/t3/t3code-cli/unwrapped.nix", package_revision)
    tag = source_ref(text)
    # Never treat a nightly, preview, non-semver, or arbitrary revision as a
    # stable packaged release. This also rejects unexpected package shapes.
    return tag if re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag) else None


def t3code_nightly_v2_status(lock):
    upstream = "pingdotgg/t3code"
    latest = api(f"repos/{upstream}/releases/latest")
    if not isinstance(latest, dict) or not isinstance(latest.get("tag_name"), str):
        raise ValueError("cannot identify latest stable T3 Code release")
    tag = latest["tag_name"]
    if latest.get("draft") is not False or latest.get("prerelease") is not False:
        raise ValueError("latest stable release is not verified")
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("unexpected stable release tag")
    if not contains(upstream, T3CODE_V2_COMMIT, tag):
        return "waiting-upstream"

    channel = api("repos/NixOS/nixpkgs/commits/nixos-unstable")
    channel_revision = channel["sha"]
    if not re.fullmatch(r"[a-f0-9]{40}", channel_revision):
        raise ValueError("invalid channel revision")
    channel_tag = t3code_stable_tag(channel_revision)
    if not channel_tag or not contains(upstream, T3CODE_V2_COMMIT, channel_tag):
        return "waiting-unstable"

    pinned_tag = t3code_stable_tag(pin(lock, "nixpkgs"))
    if not pinned_tag or not contains(upstream, T3CODE_V2_COMMIT, pinned_tag):
        return "merged-not-pinned"

    # Pin tags also need an actual, non-prerelease GitHub release. Tag
    # ancestry alone could otherwise accept a manually published preview.
    release = api(f"repos/{upstream}/releases/tags/{pinned_tag}")
    if (release.get("tag_name") != pinned_tag or
            release.get("draft") is not False or release.get("prerelease") is not False):
        raise ValueError("pinned T3 Code release is not stable")
    return "PINNED-READY"

def detect(name, lock):
    if name == "opencode-v2":
        import importlib.util
        spec = importlib.util.spec_from_file_location("release_readiness", ROOT / ".github/scripts/upstream-release-readiness.py")
        detector = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(detector)
        return detector.inspect(name, lock)["status"]
    if name == "t3code-nightly-v2":
        return t3code_nightly_v2_status(lock)
    if name == "t3code-stable010":
        # The bridging overlay is droppable under the same gate as the
        # nightly cutover: a stable V2 release carrying the root pin.
        return t3code_nightly_v2_status(lock)
    if name in PR_WAITS:
        repo, number, input_name = PR_WAITS[name]
        pr = api(f"repos/{repo}/pulls/{number}")
        if not pr.get("merged"):
            return "waiting-upstream"
        return "PINNED-READY" if contains(repo, pr["merge_commit_sha"], pin(lock, input_name)) else "merged-not-pinned"
    revision = pin(lock, "nixpkgs")
    if name == "qbittorrent":
        repo, number, package = "qbittorrent/qBittorrent", 24055, "qbittorrent"
        pr = api(f"repos/{repo}/pulls/{number}")
        if not pr.get("merged"):
            return "waiting-upstream"
        return "PINNED-READY" if package_contains(package, repo, pr["merge_commit_sha"], revision) else "merged-not-pinned"
    if name == "moonshine-pr227":
        repo, number, package = "hgaiser/moonshine", 227, "moonshine"
        pr = api(f"repos/{repo}/pulls/{number}")
        if not pr.get("merged"):
            return "waiting-upstream"
        if not package_contains(package, repo, pr["merge_commit_sha"], revision):
            return "merged-not-pinned"
        # The alpha test build also carries the local reload guard; retiring
        # it before upstream implements equivalent behavior would reintroduce
        # the reload disconnect. Require the exact guarded source.
        return "PINNED-READY" if moonshine_reload_guard(repo, revision) else "waiting-source"
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
    # The registry owns watcher IDs and lifecycle policy. Detection never writes.
    registry = json.loads((ROOT / ".github/upstream/watchers.json").read_text())
    results = {name: inspect(name, lock) for name in registry}
    if args.json:
        print(json.dumps(results, sort_keys=True))
    else:
        for name, status in results.items():
            print(f"{name}: {status}")


if __name__ == "__main__":
    main()
