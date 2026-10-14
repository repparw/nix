#!/usr/bin/env python3
"""Independent OpenCode v2 release/pin readiness detector (standalone).

Tracks the fleet's OpenCode v2 side-package migration (repository PR #222
pins 2.0.26 from Nixpkgs PR 569770, alternate Nixpkgs PR 572946 packages the
same release as `opencode_2`) without touching the shared upstream-readiness
registry, its publisher, or any production pin.

Readiness requires the *real* upstream v2 package source (anomalyco/opencode)
at or after the tested v2.0.26 tag to be packaged by BOTH the channel branch
declared by the root `nixpkgs` input in `flake.nix` (never hardcoded) and the
root `flake.lock` pin. A merged Nixpkgs packaging PR alone never retires the
overlay: merged commits can be missing from the channel, package an older
source, or ship under an unexpected attr. Only actual package-source evidence
in the channel and the pin supports `PINNED-READY`.

Unlike the T3 Code nightly-v2 detector, OpenCode v2 tags have no published
GitHub releases (its `releases/latest` still points at v1), so the gate is
tested-tag commit ancestry rather than release metadata.

Statuses: `waiting-upstream`, `waiting-unstable`, `merged-not-pinned`,
`PINNED-READY`, `completed`, and `unavailable (<ErrorName>)`. Transport
failures, malformed package sources, and unknown fetch origins fail closed to
`unavailable` — never to a waiting or ready status. `completed` additionally
requires the overlay to be gone from the checked-out tree, and only when the
pin itself packages real v2.

Output: plain text prints `opencode-v2: <status>`; `--json` prints a
structured object keyed by watcher with the chosen attr, version, source ref,
and repository for the channel and the pin.
"""
import argparse
import base64
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WATCHER = "opencode-v2"
UPSTREAM = "anomalyco/opencode"
TESTED_VERSION = "2.0.26"
TESTED_TAG = f"v{TESTED_VERSION}"
# v2-specific attrs first; plain `opencode` is included because nixpkgs may
# eventually move v2 into it. Order is the tie-break for equal versions.
CANDIDATE_ATTRS = ("opencode2", "opencode_2", "opencode")
PACKAGING_PRS = (569770, 572946)
OVERLAY_MARKER = Path("modules/_packages/opencode-v2.nix")
READY = "PINNED-READY"

_VERSION = re.compile(r'\bversion\s*=\s*"([^"]+)"\s*;')
_OWNER = re.compile(r'\bowner\s*=\s*"([^"]+)"\s*;')
_REPO = re.compile(r'\brepo\s*=\s*"([^"]+)"\s*;')
_REV = re.compile(r'\brev\s*=\s*"([^"]+)"\s*;')
_TAG = re.compile(r'\btag\s*=\s*"([^"]+)"\s*;')
_TAG_FINAL = re.compile(r"\btag\s*=\s*finalAttrs\.version\s*;")
_NIXPKGS_URL = re.compile(r'nixpkgs\.url\s*=\s*"github:NixOS/nixpkgs/([^"]+)"\s*;')
_REVISION = re.compile(r"[a-f0-9]{40}")

_TOKEN_ENV = None


def token_env():
    """Environment for gh/nh. The token is passed only via env, never logged."""
    global _TOKEN_ENV
    if _TOKEN_ENV is None:
        env = dict(os.environ)
        if not env.get("GH_TOKEN"):
            # Never print or echo the token; only its presence is checked.
            result = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, timeout=15)
            if result.returncode == 0 and result.stdout.strip():
                env["GH_TOKEN"] = result.stdout.strip()
        _TOKEN_ENV = env
    return _TOKEN_ENV


def api(endpoint):
    result = subprocess.run(
        ["gh", "api", endpoint], capture_output=True, text=True, timeout=45, check=True, env=token_env()
    )
    return json.loads(result.stdout)


def try_source(repository, path, revision):
    """Package text, or None when the attr path does not exist (HTTP 404).

    Any other transport failure raises so the caller fails closed instead of
    treating an unavailable fetch as an absent attr.
    """
    result = subprocess.run(
        ["gh", "api", f"repos/{repository}/contents/{path}?ref={revision}"],
        capture_output=True,
        text=True,
        timeout=45,
        env=token_env(),
    )
    if result.returncode != 0:
        if "HTTP 404" in result.stderr:
            return None
        result.check_returncode()
    data = json.loads(result.stdout)
    return base64.b64decode(data["content"], validate=False).decode()


def contains(repository, base, ref):
    comparison = api(f"repos/{repository}/compare/{base}...{ref}")
    return comparison.get("status") in ("ahead", "identical") and comparison["merge_base_commit"]["sha"] == base


def tested_tag_commit():
    """Commit of the tested stable v2 tag, or None when upstream has no such tag."""
    try:
        data = api(f"repos/{UPSTREAM}/commits/{TESTED_TAG}")
    except subprocess.CalledProcessError as error:
        if error.stderr and "HTTP 404" in error.stderr:
            return None
        raise
    sha = data.get("sha") if isinstance(data, dict) else None
    if not sha or not _REVISION.fullmatch(sha):
        raise ValueError("invalid tested tag commit")
    return sha


def parse_package(text):
    """Parse a by-name package.nix into its version and fetch origin.

    Versions must be plain three-part semver releases; prerelease or suffixed
    versions fail closed because their stability cannot be verified.
    """
    version = _VERSION.search(text)
    if not version:
        raise ValueError("package source does not declare a version")
    version = version.group(1)
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError(f"packaged version {version!r} is not a plain semver release")
    rev = _REV.search(text)
    tag = _TAG.search(text)
    if rev:
        ref = rev.group(1)
    elif tag and "${" in tag.group(1):
        ref = tag.group(1).replace("${finalAttrs.version}", version).replace("${version}", version)
    elif tag:
        ref = tag.group(1)
    elif _TAG_FINAL.search(text):
        ref = version
    else:
        raise ValueError("package source ref is not a literal revision or version tag")
    owner = _OWNER.search(text)
    repo = _REPO.search(text)
    source_repo = f"{owner.group(1)}/{repo.group(1)}" if owner and repo else None
    return {"version": version, "ref": ref, "source_repo": source_repo}


def version_tuple(version):
    return tuple(int(part) for part in version.split("."))


def probe_revision(repository, revision, tested_commit):
    """Inspect one nixpkgs revision for a real upstream v2 opencode source."""
    candidates = {}
    for attr in CANDIDATE_ATTRS:
        text = try_source(repository, f"pkgs/by-name/op/{attr}/package.nix", revision)
        candidates[attr] = parse_package(text) if text is not None else None
        if candidates[attr] is not None:
            candidates[attr]["attr"] = attr
    # Highest packaged version wins; attr order in CANDIDATE_ATTRS breaks ties.
    chosen = None
    for attr in CANDIDATE_ATTRS:
        candidate = candidates[attr]
        if candidate is not None and (chosen is None or version_tuple(candidate["version"]) > version_tuple(chosen["version"])):
            chosen = candidate
    real_v2 = False
    if chosen:
        if version_tuple(chosen["version"]) >= version_tuple(TESTED_VERSION):
            if chosen["source_repo"] != UPSTREAM:
                raise ValueError(f"unknown package source {chosen['source_repo']!r} for a v2 claim")
            real_v2 = contains(UPSTREAM, tested_commit, chosen["ref"])
    return {
        "revision": revision,
        "attr": chosen and chosen["attr"],
        "version": chosen and chosen["version"],
        "source_ref": chosen and chosen["ref"],
        "source_repo": chosen and chosen["source_repo"],
        "real_v2": real_v2,
        "candidates": {attr: candidate and candidate["version"] for attr, candidate in candidates.items()},
    }


def flake_branch():
    """Channel branch declared by the root nixpkgs input in flake.nix."""
    match = _NIXPKGS_URL.search((ROOT / "flake.nix").read_text())
    if not match:
        raise ValueError("flake.nix does not declare a github:NixOS/nixpkgs branch")
    return match.group(1)


def pin_revision(lock):
    node = lock["nodes"]["root"]["inputs"]["nixpkgs"]
    # Root inputs are direct references. Reject unsupported lock shapes.
    rev = lock["nodes"][node]["locked"]["rev"]
    if not _REVISION.fullmatch(rev):
        raise ValueError("invalid pinned nixpkgs revision")
    return rev


def channel_revision(branch):
    data = api(f"repos/NixOS/nixpkgs/branches/{branch}")
    sha = data.get("commit", {}).get("sha") if isinstance(data, dict) else None
    if not sha or not _REVISION.fullmatch(sha):
        raise ValueError("invalid channel revision")
    return sha


def packaging_pr_evidence(branch):
    """Nixpkgs packaging PR state and branch reachability via nh search prs.

    Informational for readiness gating (package source evidence decides), but
    required to tell `waiting-upstream` from `waiting-unstable` accurately.
    """
    evidence = []
    for number in PACKAGING_PRS:
        result = subprocess.run(
            ["nh", "search", "prs", str(number), "--days", "400", "--json"],
            capture_output=True,
            text=True,
            timeout=120,
            check=True,
            env=token_env(),
        )
        report = json.loads(result.stdout)
        match = next((entry for entry in report.get("results", []) if entry.get("number") == number), None)
        if match is None:
            raise ValueError(f"packaging PR {number} missing from nh search results")
        reachable = next(
            (entry for entry in match.get("reachability", []) if entry.get("branch") == branch), None
        )
        evidence.append(
            {
                "number": number,
                "state": match.get("state"),
                "merged": match.get("state") == "merged",
                "merge_commit_sha": match.get("merge_commit_sha"),
                "branch_reachable": reachable and reachable.get("status"),
            }
        )
    return evidence


def opencode_v2_evidence(lock, overlay_present):
    branch = flake_branch()
    pin = pin_revision(lock)
    tested = tested_tag_commit()
    evidence = {
        "watcher": WATCHER,
        "status": None,
        "tested": {"repo": UPSTREAM, "version": TESTED_VERSION, "tag": TESTED_TAG, "commit": tested},
        "flake": {"input": "nixpkgs", "branch": branch},
        "overlay": {"path": str(OVERLAY_MARKER), "present": overlay_present},
    }
    if tested is None:
        evidence["status"] = "waiting-upstream"
        evidence["reason"] = f"upstream has not tagged the tested stable v2 release {TESTED_TAG}"
        return evidence
    channel = probe_revision("NixOS/nixpkgs", channel_revision(branch), tested)
    pinned = probe_revision("NixOS/nixpkgs", pin, tested)
    evidence["channel"] = channel
    evidence["pin"] = pinned
    if channel["real_v2"] and pinned["real_v2"]:
        # Readiness comes from package source evidence only; PR state is
        # deliberately not consulted here and can never produce READY.
        evidence["status"] = READY
        return evidence
    if channel["real_v2"]:
        evidence["status"] = "merged-not-pinned"
        return evidence
    prs = packaging_pr_evidence(branch)
    evidence["packaging_prs"] = prs
    evidence["status"] = "waiting-unstable" if any(pr["merged"] for pr in prs) else "waiting-upstream"
    return evidence


def inspect(name, lock):
    if name != WATCHER:
        raise ValueError(f"unknown watcher {name}")
    try:
        evidence = opencode_v2_evidence(lock, overlay_present=(ROOT / OVERLAY_MARKER).exists())
        if evidence["status"] == READY and not evidence["overlay"]["present"]:
            # The package workaround is absent and the pin packages real v2.
            # Fleet runtime verification is a separate completion requirement.
            evidence["status"] = "completed"
        return evidence
    except (subprocess.SubprocessError, OSError, ValueError, KeyError, TypeError) as error:
        # Do not echo raw transport output, which can contain credentials.
        return {"watcher": WATCHER, "status": f"unavailable ({type(error).__name__})"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    lock = json.loads((ROOT / "flake.lock").read_text())
    evidence = inspect(WATCHER, lock)
    if args.json:
        print(json.dumps({WATCHER: evidence}, sort_keys=True))
    else:
        print(f"{WATCHER}: {evidence['status']}")


if __name__ == "__main__":
    main()
