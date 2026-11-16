#!/usr/bin/env python3
"""Start Helium on the first browser-using Browse MCP call, not MCP initialization."""

import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time

# Metadata and settings do not need a connected browser.
NO_BROWSER_TOOLS = {"status", "settings"}


def connected(browse):
    try:
        result = subprocess.run(
            [browse, "status", "--json"],
            capture_output=True,
            timeout=3,
            check=False,
        )
        status = json.loads(result.stdout)
        return bool(status.get("connected") or (status.get("extension") or {}).get("connected"))
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
    if connected(browse):
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
                [browse, "tabs"],
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
        if not isinstance(message, dict) or message.get("method") != "tools/call":
            return False
        params = message.get("params")
        if not isinstance(params, dict):
            return False
        name = params.get("name")
        if not isinstance(name, str) or name in NO_BROWSER_TOOLS:
            return False
        if name == "tabs":
            arguments = params.get("arguments")
            action = arguments.get("action", "list") if isinstance(arguments, dict) else "list"
            return action == "new"
        # OpenCode now exposes browser tools directly (navigate, click, snapshot,
        # etc.); other clients still use execute. Include future tools by default.
        return True
    except (TypeError, ValueError):
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
