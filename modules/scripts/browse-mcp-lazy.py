#!/usr/bin/env python3
"""Launch Helium only when a Browse MCP tool needs the browser."""
import fcntl
import json
import os
import re
from pathlib import Path
import subprocess
import sys
from threading import Thread
import time


# Browse 0.1.1 embeds prescriptive CAPTCHA advice in MCP instructions, tool
# descriptions and action results. Keep its diagnostics and handoff capability,
# but don't present tool advice as a rule imposed on the calling agent.
GUIDANCE_REWRITES = (
    ("Never solve a captcha yourself; hand it off.", "Use handoff for user verification when needed."),
    (
        "When only a person can proceed — login, 2FA, passkey, captcha or payment confirmation — call `handoff` with the `tab` and what the user should do, and wait. Never solve a captcha yourself and never retry-loop a blocked site.",
        "Use `handoff` with the `tab` when a step needs a person, such as 2FA or payment confirmation. Challenges can require user verification. Stop rather than retry-loop a site block.",
    ),
    (
        'When only a person can proceed — login, 2FA, passkey, captcha or payment confirmation — call `handoff("what the user should do")` and wait. Pass `start` for an action that itself blocks. Never solve a captcha yourself and never retry-loop a blocked site; if a challenge is interactive or the site refuses the visit, hand off or stop and tell the user.',
        'Use `handoff("what the user should do")` when a step needs a person; pass `start` for an action that blocks. Challenges can require user verification. Stop rather than retry-loop a site block.',
    ),
    (
        "a bot challenge: hand interactive ones to the user with handoff(), never solve or retry-loop them",
        "a detected bot challenge with its status and optional handoff() for user verification",
    ),
    (
        "- handoff(message, {timeoutMs?, start?}) when only the user can proceed (login, 2FA, captcha, payment); demonstrate(message) to watch the user do a flow.",
        "- handoff(message, {timeoutMs?, start?}) requests user interaction; demonstrate(message) lets the agent watch the user do a flow.",
    ),
    (
        "(an interactive one needs handoff(); never solve or retry-loop it)",
        "(handoff() is available for user verification; do not retry-loop a site block)",
    ),
)
CHALLENGE_ADVICE = re.compile(
    r"Don't retry, reload or try to solve it: call handoff\(.*?\) so the user does it, or stop\."
)


def rewrite_guidance(value):
    if not isinstance(value, str):
        return value
    for original, replacement in GUIDANCE_REWRITES:
        value = value.replace(original, replacement)
    return CHALLENGE_ADVICE.sub(
        "Handoff is available if user verification is required; stop on a site block.", value
    )


def rewrite_response(line):
    """Rewrite agent guidance in MCP responses, not requests or page data."""
    try:
        message = json.loads(line)
    except (UnicodeDecodeError, ValueError):
        return line
    if not isinstance(message, dict) or not isinstance(message.get("result"), dict):
        return line
    result = message["result"]
    changed = False

    def replace_field(obj, key):
        nonlocal changed
        before = obj.get(key)
        after = rewrite_guidance(before)
        if after != before:
            obj[key] = after
            changed = True

    replace_field(result, "instructions")
    tools = result.get("tools")
    if isinstance(tools, list):
        for tool in tools:
            if not isinstance(tool, dict):
                continue
            replace_field(tool, "description")
            schema = tool.get("inputSchema")
            if isinstance(schema, dict) and isinstance(schema.get("properties"), dict):
                for prop in schema["properties"].values():
                    if isinstance(prop, dict):
                        replace_field(prop, "description")
    content = result.get("content")
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict):
                replace_field(item, "text")
    if not changed:
        return line
    return (json.dumps(message, ensure_ascii=False, separators=(",", ":")) + "\n").encode()


def forward_output(stream):
    for line in stream:
        sys.stdout.buffer.write(rewrite_response(line))
        sys.stdout.buffer.flush()


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
                             stdout=subprocess.PIPE, stderr=sys.stderr.buffer)
    pump = Thread(target=forward_output, args=(child.stdout,), daemon=True)
    pump.start()
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
    pump.join()
    return child.wait()


if __name__ == "__main__":
    sys.exit(main())
