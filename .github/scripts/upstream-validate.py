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
    elif name == "cliamp-hm-module":
        settings = evaluate("alpha.config.home-manager.users.repparw.programs.cliamp.settings")
        require(settings == {"theme": "", "repeat": "Off", "shuffle": True, "provider": "spotify",
                             "spotify": {"client_id": "e79bc2a7d7f44a9e9153c0a5121ee0ce", "bitrate": 320},
                             "ytmusic": {"cookies_from": "chrome:~/.config/net.imput.helium/Default"}},
                "cliamp settings changed")
        service = unit("alpha", "cliamp")
        require("cliamp" in service["Service"]["ExecStart"] and "daemon" in service["Service"]["ExecStart"],
                "missing cliamp daemon")
        require("cliamp.sock.pid" in str(service["Service"]["ExecStartPre"]), "stale PID cleanup changed")
        build("alpha.pkgs.cliamp")
    elif name == "cliamp-attach":
        package = build("alpha.pkgs.cliamp")
        help_text = command(str(package / "bin/cliamp"), "--help")
        require(all(re.search(rf"\b{value}\b", help_text) for value in ("attach", "quit")), "missing CLI commands")
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
    elif name in ("tasks-org", "wpaperd-fix", "qbittorrent"):
        attribute = {"tasks-org": "alpha.pkgs.tasks-org", "wpaperd-fix": "alpha.pkgs.wpaperd",
                     "qbittorrent": "alpha.config.containers.qbittorrent.config.services.qbittorrent.package"}[name]
        build(attribute)
    elif name == "moonshine-pr227":
        # The candidate removes the declarative test-build aspect: the
        # generated unit must select the unpatched upstream package, the
        # reload-guard source predicate must hold (the same one readiness
        # used), and the unpatched package must build.
        import importlib.util
        spec = importlib.util.spec_from_file_location("readiness", ROOT / ".github/scripts/upstream-readiness.py")
        detector = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(detector)
        lock = json.loads((ROOT / "flake.lock").read_text())
        revision = detector.pin(lock, "nixpkgs")
        require(detector.moonshine_reload_guard("hgaiser/moonshine", revision),
                "pinned upstream Moonshine lacks the reload guard")
        package = evaluate("alpha.config.services.moonshine.package.outPath")
        require(package == evaluate("alpha.pkgs.moonshine.outPath"),
                "Alpha must select the unpatched upstream Moonshine")
        build("alpha.pkgs.moonshine")
    elif name == "t3code-stable010":
        # The candidate completes the direct cutover: the bridging aspect
        # is gone, the version assertion guards the pin, and every host
        # serves the root-pin package (Alpha stock, Pi/Epsilon the split
        # server-only build).
        import importlib.util
        spec = importlib.util.spec_from_file_location("readiness", ROOT / ".github/scripts/upstream-readiness.py")
        detector = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(detector)
        lock = json.loads((ROOT / "flake.lock").read_text())
        require(detector.t3code_nightly_v2_status(lock) == "PINNED-READY",
                "root pin must carry a stable orchestrator-v2 release")
        for host in ("alpha", "pi", "epsilon"):
            service = unit(host, "t3code-web")
            require("--mode web" in service["Service"]["ExecStart"], "missing web arguments")
            package = evaluate(f"{host}.config.home-manager.users.repparw.programs.t3code.package.outPath")
            has_cli = json.loads(command("nix", "eval", "--json", "--no-update-lock-file",
                                         f".#nixosConfigurations.{host}.pkgs", "--apply", "p: p ? t3code-cli"))
            cli = evaluate(f"{host}.pkgs.t3code-cli.outPath") if has_cli else package
            require(service["Service"]["ExecStart"].startswith(cli + "/bin/t3 "),
                    f"{host} must serve the selected CLI")
        version = command("nix", "eval", "--raw", "--no-update-lock-file",
                          ".#nixosConfigurations.alpha.config.home-manager.users.repparw.programs.t3code.package.version")
        match = re.match(r"(\d+)\.(\d+)\.(\d+)", version)
        require(match and tuple(int(part) for part in match.groups()) >= (0, 1, 0),
                f"pinned t3code {version} is below 0.1.0")
        build("alpha.config.home-manager.users.repparw.programs.t3code.package")
    else:
        raise ValueError(f"no package validation for {name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("watcher")
    parser.add_argument("--architecture", choices=("x86", "arm"), default="x86")
    arguments = parser.parse_args()
    validate(arguments.watcher, arguments.architecture)
    print(f"Verified {arguments.watcher} on {arguments.architecture}")
