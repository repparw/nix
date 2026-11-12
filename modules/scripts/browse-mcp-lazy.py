#!/usr/bin/env python3
"""Start Helium on the first browser-using Browse MCP call, not MCP initialization."""

import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time

# These tools need a connected browser. Metadata and session inspection do not.
BROWSER_TOOLS = {
    "execute",
    "session_new",
    "session_adopt",
    "network",
    "recording",
    "flight_recorder",
    "secrets_run",
    "secrets_refresh",
}


def connected(browse):
    try:
        result = subprocess.run(
            [browse, "status", "--json"],
            capture_output=True,
            timeout=3,
            check=False,
        )
        return bool(json.loads(result.stdout).get("extension", {}).get("connected"))
    except (OSError, ValueError, subprocess.TimeoutExpired, AttributeError):
        return False


def running(pgrep):
    try:
        return subprocess.run(
            [pgrep, "-u", str(os.getuid()), "-x", "helium"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
            check=False,
        ).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def prepare_browser(browse, helium, pgrep):
    # Avoid starting the Node.js status CLI on every browser tool call.
    # Browse itself handles reconnection when Helium is already running.
    if running(pgrep) or connected(browse):
        return

    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/browse-{os.getuid()}"))
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Several MCP clients can start simultaneously; only one should launch Helium.
    with (runtime / "browse-helium.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if connected(browse):
            return
        try:
            # Browse's relay starts on demand. Start it before Helium so the
            # extension can reconnect while the browser is opening.
            subprocess.run(
                [browse, "settings", "get", "--json"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=12,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass

        if not running(pgrep):
            try:
                subprocess.Popen(
                    [helium],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except OSError as error:
                print(f"browse-mcp: could not launch Helium: {error}", file=sys.stderr)
                return

        # A normal Browse tool call does not wait for a browser that was closed
        # while its relay was running. Give the extension time to reconnect.
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if connected(browse):
                return
            time.sleep(0.4)
        print("browse-mcp: Helium's Browse extension did not reconnect", file=sys.stderr)


def needs_browser(line):
    try:
        message = json.loads(line)
        return (
            isinstance(message, dict)
            and message.get("method") == "tools/call"
            and isinstance(message.get("params"), dict)
            and message["params"].get("name") in BROWSER_TOOLS
        )
    except ValueError:
        return False


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: browse-mcp-lazy.py <browse> <helium> <pgrep>")
    browse, helium, pgrep = sys.argv[1:]
    # Preserve the original MCP server and protocol. Only inspect incoming
    # newline-delimited JSON-RPC requests; forward bytes unchanged.
    child = subprocess.Popen(
        [browse, "mcp"], stdin=subprocess.PIPE, stdout=sys.stdout.buffer, stderr=sys.stderr.buffer
    )
    try:
        for line in sys.stdin.buffer:
            if needs_browser(line):
                prepare_browser(browse, helium, pgrep)
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
