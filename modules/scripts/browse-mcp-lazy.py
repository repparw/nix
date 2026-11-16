#!/usr/bin/env python3
"""Launch Helium only when a Browse MCP tool needs the browser."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def needs_browser(line):
    try:
        request = json.loads(line)
    except (ValueError, UnicodeDecodeError):
        return False
    if not isinstance(request, dict) or request.get("method") != "tools/call":
        return False
    params = request.get("params")
    if not isinstance(params, dict):
        return False
    if params.get("name") == "tabs":
        args = params.get("arguments")
        return isinstance(args, dict) and args.get("action") == "new"
    return isinstance(params.get("name"), str) and params["name"] != "status"


def connected(browse):
    try:
        result = subprocess.run([browse, "status", "--json"], capture_output=True, timeout=2)
        return json.loads(result.stdout).get("connected") is True
    except (OSError, ValueError, AttributeError, subprocess.TimeoutExpired):
        return False


def ensure_browser(browse, helium, pgrep):
    if connected(browse):
        return
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/browse-{os.getuid()}"))
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (runtime / "browse-helium.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if connected(browse):
            return
        try:
            running = subprocess.run(
                [pgrep, "-u", str(os.getuid()), "-x", "helium"],
                stdout=subprocess.DEVNULL, timeout=2,
            ).returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            running = False
        if not running:
            # The extension needs a listening relay when Helium opens.
            try:
                subprocess.run([browse, "tabs"], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=8)
            except (OSError, subprocess.TimeoutExpired):
                pass
            try:
                subprocess.Popen([helium], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 start_new_session=True)
            except OSError as error:
                print(f"browse-mcp: could not start Helium: {error}", file=sys.stderr)
                return
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            if connected(browse):
                return
            time.sleep(0.4)
        print("browse-mcp: Helium's Browse extension did not reconnect", file=sys.stderr)


def main():
    browse, helium, pgrep = sys.argv[1:]
    child = subprocess.Popen([browse, "mcp"], stdin=subprocess.PIPE,
                             stdout=sys.stdout.buffer, stderr=sys.stderr.buffer)
    try:
        for line in sys.stdin.buffer:
            if needs_browser(line):
                ensure_browser(browse, helium, pgrep)
            try:
                child.stdin.write(line)
                child.stdin.flush()
            except BrokenPipeError:
                break
    finally:
        child.stdin.close()
    return child.wait()


if __name__ == "__main__":
    sys.exit(main())
