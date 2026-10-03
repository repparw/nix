"""Prune only Pi system generations, then collect unrooted store paths."""
import argparse
import fcntl
from pathlib import Path
import re
import subprocess
import sys


def command(*args):
    return subprocess.check_output(args, text=True).splitlines()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["plan", "apply"])
    parser.add_argument("--keep", type=int, default=5)
    parser.add_argument("--profile", type=Path, default=Path("/nix/var/nix/profiles/system"))
    parser.add_argument("--current", type=Path, default=Path("/run/current-system"))
    parser.add_argument("--booted", type=Path, default=Path("/run/booted-system"))
    parser.add_argument("--gcroots", type=Path, default=Path("/nix/var/nix/gcroots"))
    parser.add_argument("--lock", type=Path, default=Path("/run/fleet-update.lock"))
    args = parser.parse_args()
    if args.keep < 2:
        parser.error("--keep must retain at least two system generations")

    with args.lock.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Pi retention deferred: another fleet operation holds the lock")
            return

        # Nix protects these roots independently of profile-generation links.
        protected = {args.current.resolve(strict=True), args.booted.resolve(strict=True)}
        for name, target in [("current-system", args.current), ("booted-system", args.booted)]:
            if (args.gcroots / name).resolve(strict=True) != target.resolve(strict=True):
                raise ValueError(f"GC root {name} does not protect its runtime system")
        selected = args.profile.resolve(strict=True)
        generations = []
        pattern = re.compile(re.escape(args.profile.name) + r"-([0-9]+)-link")
        for link in args.profile.parent.iterdir():
            match = pattern.fullmatch(link.name)
            if match and link.is_symlink():
                generations.append((int(match[1]), link.resolve(strict=True)))
        if not generations or not any(target == selected for _, target in generations):
            raise ValueError("current profile has no valid generation link")
        generations.sort(reverse=True)
        keep = {number for number, _ in generations[:args.keep]}
        for number, target in generations:
            # deploy-rs profiles can wrap the real NixOS system. Compare the
            # closure, not just the wrapper path, with current/booted systems.
            closure = {Path(path) for path in command("nix-store", "--query", "--requisites", str(target))}
            if target == selected or protected.intersection(closure):
                keep.add(number)
        prune = [str(number) for number, _ in generations if number not in keep]
        print("Retain system generations:", " ".join(map(str, sorted(keep))))
        print("Eligible system generations:", " ".join(prune) or "none", flush=True)
        if args.mode == "apply":
            if prune:
                subprocess.run(["nix-env", "--profile", str(args.profile), "--delete-generations", *prune], check=True)
            # No -d or --delete-older-than: leave all other profiles, preparation
            # roots, and fleet-update/previous rollback roots untouched.
            subprocess.run(["nix-collect-garbage"], check=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Pi retention aborted: {error}", file=sys.stderr)
        sys.exit(1)
