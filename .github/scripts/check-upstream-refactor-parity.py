#!/usr/bin/env python3
"""One-time #404 parity gate: compare the evaluated fleet against the PR base.

Do not merge a structural relocation that changes selected packages or
service state. The wpaperd patch source changes deliberately, so compare
its fetched normalized content to the previous vendored patch instead of
requiring the patch derivation's store path to remain identical.
"""
import difflib
import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
BASE = os.environ["UPSTREAM_PARITY_BASE"]
EVAL = r"""
let
  fleet = builtins.getFlake (toString ./.);
  alpha = fleet.nixosConfigurations.alpha;
  pi = fleet.nixosConfigurations.pi;
  epsilon = fleet.nixosConfigurations.epsilon;
in {
  alpha = {
    niri = alpha.config.programs.niri.enable;
    gamescopeVersion = alpha.pkgs.gamescope.version;
    gamescopePostPatch = alpha.pkgs.gamescope.postPatch;
    tasksOrg = alpha.pkgs.tasks-org.drvPath;
    wpaperdVersion = alpha.pkgs.wpaperd.version;
    wpaperdSource = alpha.pkgs.wpaperd.src.outPath;
    wpaperdPatchCount = builtins.length alpha.pkgs.wpaperd.patches;
    qbittorrent = alpha.config.containers.qbittorrent.config.services.qbittorrent.package.drvPath;
    moonshine = alpha.config.services.moonshine.package.drvPath;
    t3code = alpha.config.home-manager.users.repparw.programs.t3code.package.drvPath;
  };
  pi.t3code = pi.config.home-manager.users.repparw.programs.t3code.package.drvPath;
  epsilon.t3code = epsilon.config.home-manager.users.repparw.programs.t3code.package.drvPath;
}
"""


def command(*args, cwd=ROOT):
    return subprocess.run(args, cwd=cwd, text=True, check=True, capture_output=True).stdout.strip()


def snapshot(repo):
    payload = json.loads(command(
        "nix", "eval", "--impure", "--json", "--no-write-lock-file",
        "--expr", EVAL, cwd=repo,
    ))
    # Moving a Nix indented-string literal can alter indentation without
    # changing the shell commands it executes.
    payload["alpha"]["gamescopePostPatch"] = " ".join(
        payload["alpha"]["gamescopePostPatch"].split()
    )
    return payload


def fetched_wpaperd_patch(repo):
    patch = command(
        "nix", "build", "--impure", "--no-link", "--print-out-paths",
        "--no-write-lock-file", "--expr",
        "let fleet = builtins.getFlake (toString ./.); "
        "in builtins.elemAt fleet.nixosConfigurations.alpha.pkgs.wpaperd.patches 0",
        cwd=repo,
    )
    return Path(patch).read_bytes()


def main():
    command("git", "fetch", "--no-tags", "--depth=1", "origin", BASE)
    with tempfile.TemporaryDirectory(prefix="upstream-parity-") as directory:
        before = Path(directory) / "before"
        command("git", "worktree", "add", "--detach", str(before), BASE)
        try:
            old = snapshot(before)
            new = snapshot(ROOT)
            if old != new:
                difference = "".join(difflib.unified_diff(
                    json.dumps(old, indent=2, sort_keys=True).splitlines(keepends=True),
                    json.dumps(new, indent=2, sort_keys=True).splitlines(keepends=True),
                    fromfile="base evaluated configuration",
                    tofile="refactor evaluated configuration",
                ))
                raise AssertionError("Fleet configuration differs:\n" + difference)
            expected_patch = (
                before / "modules/aspects/gui/wpaperd-output-removal-race.patch"
            ).read_bytes()
            actual_patch = fetched_wpaperd_patch(ROOT)
            if actual_patch != expected_patch:
                raise AssertionError(
                    f"wpaperd fetched patch differs from prior vendor copy: "
                    f"{len(actual_patch)} vs {len(expected_patch)} bytes"
                )
            print("Configuration parity passed for Alpha/Pi/Epsilon.")
            print("Fetched wpaperd patch bytes match the original vendored fix.")
        finally:
            command("git", "worktree", "remove", "--force", str(before))


if __name__ == "__main__":
    main()
