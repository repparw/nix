"""Shared deterministic deletion for self-contained upstream workarounds."""

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def module_path(name, spec):
    if not re.fullmatch(r"[a-z0-9-]+", name) or spec.get("mode") != "post-lock":
        raise ValueError("invalid removable upstream watcher")
    return f"modules/aspects/upstream/{name}.nix"


def remove_module(name, spec, cwd=ROOT):
    path = module_path(name, spec)
    subprocess.run(["git", "rm", "--", path], cwd=cwd, check=True,
                   capture_output=True, text=True)
    return path
