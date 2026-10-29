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
}
WORKAROUNDS = {
    "authelia-pnpm-hash": ("modules/_services/authelia.nix", "autheliaPackage"),
    "t3code-connect": ("modules/aspects/upstream/t3code-connect.nix", "cp .env.example .env"),
    "t3code-split": ("modules/aspects/upstream/t3code-split.nix", "t3code-server ="),
    "tasks-org": ("modules/aspects/upstream/tasks-org.nix", None),
    "t3code-browser-libs": (
        "modules/aspects/upstream/t3code-browser-libs.nix", "programs.nix-ld.libraries"),
    "qbittorrent": ("modules/aspects/upstream/qbittorrent.nix", None),
    "wpaperd-fix": ("modules/aspects/upstream/wpaperd-fix.nix", None),
    "voxtype-graphical": ("modules/aspects/ai/voxtype-graphical-workaround.nix", None),
    "gamescope-vkroots": ("modules/aspects/upstream/gamescope-vkroots.nix", None),
    "t3code-nightly-v2": ("modules/aspects/ai/t3code-nightly.nix", None),
    "t3code-stable010": ("modules/aspects/upstream/t3code-stable010.nix", None),
    "moonshine-pr227": ("modules/aspects/upstream/moonshine-pr227-test.nix", None),
    "nodejs-security": ("modules/aspects/upstream/nodejs-security.nix", "../../_packages/nodejs-security.nix"),
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
T3CODE_STABLE_MIN_VERSION = (0, 1, 3)
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


T3CODE_PACKAGE = "pkgs/by-name/t3/t3code/package.nix"


def t3code_browser_wrapped(revision):
    # The system-wide list is only redundant when upstream's t3code wrapper
    # itself prefixes LD_LIBRARY_PATH with the browser library set
    # (NixOS/nixpkgs#575675). A merge that merely touches the package would
    # leave the downloaded headless browser broken after cleanup.
    text = source("NixOS/nixpkgs", T3CODE_PACKAGE, revision)
    return ("LD_LIBRARY_PATH" in text and
            all(library in text for library in ("libgbm", "nss", "libxkbcommon")))


def t3code_nightly_v2_status(lock, minimum_version=(0, 0, 0)):
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
    def eligible(tag):
        return (tag is not None and
                tuple(map(int, tag[1:].split("."))) >= minimum_version and
                contains(upstream, T3CODE_V2_COMMIT, tag))

    channel_tag = t3code_stable_tag(channel_revision)
    if not eligible(channel_tag):
        return "waiting-unstable"

    pinned_tag = t3code_stable_tag(pin(lock, "nixpkgs"))
    if not eligible(pinned_tag):
        return "merged-not-pinned"

    # Pin tags also need an actual, non-prerelease GitHub release. Tag
    # ancestry alone could otherwise accept a manually published preview.
    release = api(f"repos/{upstream}/releases/tags/{pinned_tag}")
    if (release.get("tag_name") != pinned_tag or
            release.get("draft") is not False or release.get("prerelease") is not False):
        raise ValueError("pinned T3 Code release is not stable")
    return "PINNED-READY"

GE_UPSTREAM = "GloriousEggroll/proton-ge-custom"
GE_PACKAGE = "pkgs/by-name/pr/proton-ge-bin/package.nix"


def ge_version(tag):
    match = re.fullmatch(r"GE-Proton([0-9]+)-([0-9]+)", tag)
    if not match:
        raise ValueError("unexpected GE stable release tag")
    return tuple(map(int, match.groups()))


def ge_stable_release(release):
    tag = release["tag_name"]
    ge_version(tag)
    if release.get("draft") is not False or release.get("prerelease") is not False:
        raise ValueError("GE release is not stable")
    return tag


def ge_package_contains(revision, commit):
    text = source("NixOS/nixpkgs", GE_PACKAGE, revision)
    match = re.search(r'\bversion\s*=\s*"(GE-Proton[0-9]+-[0-9]+)";', text)
    # Verify the actual x86_64 upstream archive, not just a version string.
    archive = ('https://github.com/GloriousEggroll/proton-ge-custom/releases/'
               'download/${finalAttrs.version}/${finalAttrs.version}-x86_64.tar.gz')
    if not match or f'url = "{archive}";' not in text:
        raise ValueError("unknown GE package source")
    tag = match.group(1)
    release = api(f"repos/{GE_UPSTREAM}/releases/tags/{tag}")
    if ge_stable_release(release) != tag:
        raise ValueError("GE package release mismatch")
    return contains(GE_UPSTREAM, commit, tag)


def fsr4_rdna2_status(lock):
    spec = json.loads((ROOT / ".github/upstream/watchers.json").read_text())["fsr4-rdna2"]
    commit = spec.get("support_commit")
    if commit is None:
        # Discovery only. Release prose can flag a candidate, never establish
        # Linux/RDNA2 usability. A reviewed and tested commit arms pin tracking.
        releases = api(f"repos/{GE_UPSTREAM}/releases?per_page=100")
        if not isinstance(releases, list) or not releases:
            raise ValueError("cannot bound GE release discovery")
        candidates = []
        reached_baseline = False
        for release in releases:
            if release.get("draft") or release.get("prerelease"):
                continue
            tag = ge_stable_release(release)
            if ge_version(tag) <= ge_version(spec["baseline_release"]):
                reached_baseline = True
                continue
            body = release.get("body")
            if not isinstance(body, str):
                raise ValueError("missing GE release notes")
            if re.search(r"\b(?:FSR\s*4(?:\.1)?|RDNA\s*2|RX\s*6[0-9]{3})\b", body, re.I):
                candidates.append(tag)
        if len(releases) >= 100 and not reached_baseline:
            raise ValueError("GE discovery exhausted before baseline")
        return ("upstream-review-required:" + max(candidates, key=ge_version)
                if candidates else "waiting-upstream")
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("support_commit must be a reviewed full SHA")
    latest = ge_stable_release(api(f"repos/{GE_UPSTREAM}/releases/latest"))
    if not contains(GE_UPSTREAM, commit, latest):
        return "waiting-upstream"
    node = lock["nodes"][lock["nodes"]["root"]["inputs"]["nixpkgs"]]
    branch = node["original"]["ref"]
    if not re.fullmatch(r"[a-zA-Z0-9._/-]+", branch):
        raise ValueError("invalid Nixpkgs channel")
    channel = api(f"repos/NixOS/nixpkgs/commits/{branch}")["sha"]
    if not re.fullmatch(r"[a-f0-9]{40}", channel):
        raise ValueError("invalid Nixpkgs channel revision")
    if not ge_package_contains(channel, commit):
        return "waiting-unstable"
    return "PINNED-READY" if ge_package_contains(pin(lock, "nixpkgs"), commit) else "merged-not-pinned"


def detect(name, lock):
    if name == "nodejs-security":
        revision = pin(lock, "nixpkgs")
        # A Node release alone is insufficient: Nix links Brotli and c-ares
        # as shared libraries, and OpenCode embeds the Bun runtime. The
        # cleanup retires the whole #341 overlay family at once, so every
        # piece must be contained by the pin before it fires.
        bun = api("repos/NixOS/nixpkgs/pulls/577354")
        if not bun.get("merged"):
            return "waiting-upstream"
        fixes = (
            "2794b31601c683d494c898a548e3c5237fa2242e",  # Node 24.22.1
            "664dc1852b684a2db1d7734514030739fc557b91",  # Brotli 1.2.1, carries the out-of-bound-write fix
            "dfbfe7d499556a3acea67ccc4888c2ef489bade0",  # c-ares 1.34.9
        )
        ready = contains("NixOS/nixpkgs", bun["merge_commit_sha"], revision)
        ready = ready and all(contains("NixOS/nixpkgs", fix, revision) for fix in fixes)
        return "PINNED-READY" if ready else "merged-not-pinned"
    if name == "fsr4-rdna2":
        return fsr4_rdna2_status(lock)
    if name == "tridactyl-reader":
        pr = api("repos/tridactyl/tridactyl/pulls/5515")
        if not pr.get("merged"):
            return "waiting-upstream"
        # The browser uses firefox-addons, not Nixpkgs' native messaging host.
        # Read its selected manifest through Nix; GitHub's contents API omits
        # the body of this >1 MB generated file.
        import os
        expression = '''let f = builtins.getFlake (builtins.getEnv "UPSTREAM_WATCH_ROOT");
          input = f.inputs.firefox-addons;
          addons = builtins.fromJSON (builtins.readFile (input.outPath + "/firefox-addons-generated.json"));
          in { revision = input.rev;
            addons = builtins.filter (a: a.pname == "tridactyl-vim") addons; }'''
        result = subprocess.run(
            ["nix", "eval", "--impure", "--json", "--no-update-lock-file", "--expr", expression],
            env={**os.environ, "UPSTREAM_WATCH_ROOT": str(ROOT)},
            capture_output=True, text=True, timeout=120, check=True)
        selected = json.loads(result.stdout)
        if selected["revision"] != pin(lock, "firefox-addons") or len(selected["addons"]) != 1:
            raise ValueError("cannot identify the pinned Tridactyl add-on")
        addon = selected["addons"][0]
        version = addon["version"]
        if (addon["addonId"] != "tridactyl.vim@cmcaine.co.uk" or
                not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version)):
            raise ValueError("unexpected Tridactyl release metadata")
        return "PINNED-READY" if contains("tridactyl/tridactyl", pr["merge_commit_sha"], version) else "merged-not-pinned"
    if name == "opencode-v2":
        import importlib.util
        spec = importlib.util.spec_from_file_location("release_readiness", ROOT / ".github/scripts/upstream-release-readiness.py")
        detector = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(detector)
        return detector.inspect(name, lock)["status"]
    if name == "t3code-nightly-v2":
        return t3code_nightly_v2_status(lock)
    if name == "t3code-stable010":
        # Removing the bridge must not downgrade the installed stable version.
        return t3code_nightly_v2_status(lock, minimum_version=T3CODE_STABLE_MIN_VERSION)
    if name in PR_WAITS:
        repo, number, input_name = PR_WAITS[name]
        pr = api(f"repos/{repo}/pulls/{number}")
        if not pr.get("merged"):
            return "waiting-upstream"
        return "PINNED-READY" if contains(repo, pr["merge_commit_sha"], pin(lock, input_name)) else "merged-not-pinned"
    if name == "t3code-browser-libs":
        pr = api("repos/NixOS/nixpkgs/pulls/575675")
        if not pr.get("merged"):
            return "waiting-upstream"
        revision = pin(lock, "nixpkgs")
        if not contains("NixOS/nixpkgs", pr["merge_commit_sha"], revision):
            return "merged-not-pinned"
        return "PINNED-READY" if t3code_browser_wrapped(revision) else "waiting-source"
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

