"""Run the generated policy installer without touching the host's /etc."""

import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

script = Path(sys.argv[1]).read_text()
with tempfile.TemporaryDirectory() as directory:
    policy = Path(directory) / "managed"
    command = script.replace("/etc/chromium/policies/managed", str(policy))
    subprocess.run(["bash", "-e", "-c", command], check=True)
    files = sorted(policy.glob("*.json"))
    assert {path.name for path in files} == {"extra.json", "helium-nixos.json"}
    before = {
        path.name: (path.stat().st_ino, path.stat().st_mtime_ns, path.read_bytes())
        for path in files
    }

    # Chromium watches this directory. Identical policies must emit no writes,
    # attribute changes, renames or deletions that could trigger reinstallation.
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK)
    assert fd >= 0
    try:
        assert libc.inotify_add_watch(fd, os.fsencode(policy), 0xFCE) >= 0
        subprocess.run(["bash", "-e", "-c", command], check=True)
        try:
            events = os.read(fd, 65536)
        except BlockingIOError:
            events = b""
        assert not events, "unchanged activation emitted policy change events"
    finally:
        os.close(fd)
    assert before == {
        path.name: (path.stat().st_ino, path.stat().st_mtime_ns, path.read_bytes())
        for path in files
    }

    # A genuine content change still needs to converge to the declared policy.
    target = policy / "helium-nixos.json"
    expected = target.read_bytes()
    target.write_text("{}")
    subprocess.run(["bash", "-e", "-c", command], check=True)
    assert target.read_bytes() == expected
    settings = json.loads(expected)["ExtensionSettings"]
    assert len(settings) == 6
    assert all(value["installation_mode"] == "normal_installed" for value in settings.values())
