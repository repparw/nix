#!/usr/bin/env python3
"""Build cleanup packages and inspect generated behavior on the candidate SHA."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def command(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout.strip()


def evaluate(attribute):
    return json.loads(command("nix", "eval", "--json", "--no-update-lock-file", f".#nixosConfigurations.{attribute}"))


def build(attribute):
    return Path(command("nix", "build", "--no-link", "--print-out-paths",
                        "--no-update-lock-file", f".#nixosConfigurations.{attribute}"))


def unit(host, name):
    service = evaluate(f"{host}.config.home-manager.users.repparw.systemd.user.services.{name}")
    start = service["Service"]["ExecStart"]
    if isinstance(start, list):
        require(len(start) == 1, f"{host}/{name} must have exactly one ExecStart")
        service["Service"]["ExecStart"] = start[0]
    return service


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(name, architecture):
    if architecture == "arm":
        require(name == "t3code-split", "unexpected native ARM request")
        for host in ("pi", "epsilon"):
            package = build(f"{host}.config.home-manager.users.repparw.programs.t3code.package")
            upstream = evaluate(f"{host}.pkgs.t3code-cli.outPath")
            require(str(package) == upstream, f"{host} must select the upstream CLI")
            closure = command("nix", "path-info", "--recursive", str(package)).splitlines()
            require(not any(re.search(r"-electron-[0-9]", path) for path in closure),
                    f"{host} CLI closure contains Electron")
        return
    if name == "t3code-connect":
        split = json.loads(command("nix", "eval", "--json", "--no-update-lock-file",
                                   ".#nixosConfigurations.alpha.pkgs", "--apply", "p: p ? t3code-cli"))
        package = build("alpha.pkgs.t3code-desktop" if split else "alpha.pkgs.t3code")
        entries = build("alpha.config.home-manager.users.repparw.home.path")
        desktop = (entries / "share/applications/t3code.desktop").read_text()
        require("x-scheme-handler/t3code" in desktop and "%U" in desktop,
                "desktop entry must support Connect URLs")
        defaults = evaluate("alpha.config.home-manager.users.repparw.xdg.mimeApps.defaultApplications")
        require("t3code.desktop" in defaults.get("x-scheme-handler/t3code", []),
                "Connect scheme must have a default handler")
        unwrapped = build("alpha.pkgs.t3code-desktop.unwrapped" if split else "alpha.pkgs.t3code.unwrapped")
        # Server bundles include the web client; Electron's main process only
        # embeds the publishable key and delegates relay authentication to it.
        values = ("pk_live_Y2xlcmsudDMuY29kZXMk", "t3-relay", "hzxSgY2cH10sDU2r", "https://relay.t3.codes")
        for area, expected in (("server", values), ("desktop", values[:1])):
            files = [path for path in (unwrapped / f"libexec/t3code/apps/{area}").rglob("*")
                     if path.suffix in (".mjs", ".js", ".cjs") and "node_modules" not in path.parts]
            text = "\n".join(path.read_text(errors="replace") for path in files)
            require(all(value in text for value in expected), f"Connect identifiers missing in {area} bundle")
    elif name == "t3code-split":
        package = build("alpha.config.home-manager.users.repparw.programs.t3code.package")
        require(str(package) == evaluate("alpha.pkgs.t3code-desktop.outPath"),
                "Alpha must select the upstream desktop package")
    elif name == "t3code-server":
        for host in ("alpha", "pi", "epsilon"):
            service = unit(host, "t3code")
            require("--mode web" in service["Service"]["ExecStart"], "missing web arguments")
            require(service["Service"]["Restart"] == "always", "restart policy changed")
            environment = service["Service"]["Environment"]
            require(all(any(value.startswith(key + "=") for value in environment) for key in
                        ("T3CODE_CLERK_PUBLISHABLE_KEY", "T3CODE_CLERK_JWT_TEMPLATE",
                         "T3CODE_CLERK_CLI_OAUTH_CLIENT_ID", "T3CODE_RELAY_URL")), "missing Connect environment")
            package = evaluate(f"{host}.config.home-manager.users.repparw.programs.t3code.package.outPath")
            require(service["Service"]["ExecStart"].startswith(package + "/bin/t3 "), "server package changed")
        build("alpha.config.home-manager.users.repparw.programs.t3code.package")
    elif name == "gamescope-vkroots":
        # Same raw-package source predicate as readiness, after removing the
        # local override. Then build the real WSI package, without stubs.
        import importlib.util
        spec = importlib.util.spec_from_file_location("readiness", ROOT / ".github/scripts/upstream-readiness.py")
        detector = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(detector)
        require(detector.gamescope_fixed(), "flagged queue fix absent from patched upstream source")
        expression = 'let f = builtins.getFlake (builtins.getEnv "UPSTREAM_WATCH_ROOT"); in f.inputs.nixpkgs.legacyPackages.x86_64-linux.gamescope.override { enableWsi = true; }'
        subprocess.run(["nix", "build", "--impure", "--no-link", "--no-write-lock-file", "--expr", expression],
                       env={**os.environ, "UPSTREAM_WATCH_ROOT": str(ROOT)}, check=True)
    elif name in ("ashell-aws-lc", "zapfast-openssl"):
        # The cleanup removes an inline override. Build the package selected
        # by Alpha after it falls back to the pinned Nixpkgs definition.
        build("alpha.pkgs.ashell" if name == "ashell-aws-lc" else "alpha.pkgs.zapfast")
    elif name in ("tasks-org", "wpaperd-fix", "qbittorrent"):
        attribute = {"tasks-org": "alpha.pkgs.tasks-org", "wpaperd-fix": "alpha.pkgs.wpaperd",
                     "qbittorrent": "alpha.config.containers.qbittorrent.config.services.qbittorrent.package"}[name]
        build(attribute)
    else:
        raise ValueError(f"no package validation for {name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("watcher")
    parser.add_argument("--architecture", choices=("x86", "arm"), default="x86")
    arguments = parser.parse_args()
    validate(arguments.watcher, arguments.architecture)
    print(f"Verified {arguments.watcher} on {arguments.architecture}")
