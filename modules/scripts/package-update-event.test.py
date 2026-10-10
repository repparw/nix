import importlib.util
import io
import json
from pathlib import Path
import sys
import unittest

spec = importlib.util.spec_from_file_location("package_update_event", Path(sys.argv.pop(1)))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def transitions(*lines):
    return "\n".join(lines) + "\n"


class ParserTests(unittest.TestCase):
    def test_version_transition_extracted(self):
        packages = mod.parse_diff(transitions(
            "mesa: 26.2.2 ⟶ 26.2.4, 2.1 MiB",
            "irrelevant-other: 1.0 ⟶ 2.0",
        ))
        self.assertEqual(packages, [{"name": "mesa", "from": "26.2.2", "to": "26.2.4"}])

    def test_comma_separated_names_keep_first_relevant(self):
        packages = mod.parse_diff(transitions(
            "firefox, firefox-unwrapped: 150.0 ⟶ 151.0, 3.0 MiB",
        ))
        self.assertEqual(packages, [{"name": "firefox", "from": "150.0", "to": "151.0"}])

    def test_additions_and_removals_omitted(self):
        packages = mod.parse_diff(transitions(
            "steam: ∅ ⟶ ε",
            "oldpkg: 1.0 ⟶ ∅",
        ))
        self.assertEqual(packages, [])

    def test_size_only_rebuilds_omitted(self):
        packages = mod.parse_diff(transitions(
            "mesa: 2.1 MiB",
            "chromium: 900.0 KiB",
        ))
        self.assertEqual(packages, [])

    def test_epsilon_version_maps_to_empty(self):
        packages = mod.parse_diff(transitions(
            "moonshine: ε ⟶ 0.16.1",
        ))
        self.assertEqual(packages, [{"name": "moonshine", "from": "", "to": "0.16.1"}])

    def test_prefix_matches_and_others_do_not(self):
        packages = mod.parse_diff(transitions(
            "nix-2.31: 2.31.0 ⟶ 2.31.1",
            "nixos-system-alpha: 26.11.a ⟶ 26.11.b",
        ))
        self.assertEqual([p["name"] for p in packages], ["nix-2.31"])

    def test_kernel_and_nix_names_match_without_matching_nixos(self):
        packages = mod.parse_diff(transitions("linux: 6.16 ⟶ 6.17", "nix: 2.31 ⟶ 2.32", "nixos-system-alpha: old ⟶ new"))
        self.assertEqual([item["name"] for item in packages], ["linux", "nix"])

    def test_cap_at_32_packages(self):
        lines = [f"mesa-pkg{i}: 1 ⟶ 2" for i in range(40)]
        self.assertEqual(len(mod.parse_diff(transitions(*lines))), 32)


class EventTests(unittest.TestCase):
    def test_event_shape_and_deterministic_id(self):
        diff = transitions("mesa: 26.2.2 ⟶ 26.2.4")
        import contextlib
        import tempfile
        original = sys.argv
        with tempfile.NamedTemporaryFile("w", suffix=".diff", delete=False) as handle:
            handle.write(diff)
            handle.flush()
            path = Path(handle.name)
        try:
            sys.argv = ["package-update-event.py", "alpha", "26.11.20261010.4907291", str(path)]
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                mod.main()
        finally:
            path.unlink(missing_ok=True)
        sys.argv = original
        event = json.loads(buffer.getvalue())
        self.assertEqual(event["schema_version"], 1)
        self.assertEqual(event["host"], "alpha")
        self.assertEqual(event["revision"], "26.11.20261010.4907291")
        self.assertEqual(len(event["event_id"]), 64)
        self.assertEqual({p["name"] for p in event["packages"]}, {"mesa"})

    def test_durable_outbox_reuses_identical_bytes_across_clock_changes(self):
        import contextlib
        import tempfile
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            diff = Path(directory) / "diff"
            diff.write_text("mesa: 26.2.2 ⟶ 26.2.4\n")
            queued = Path(directory) / "outbox" / "event.json"
            argv = ["package-update-event.py", "alpha", "a" * 40, str(diff), "--outbox-entry", str(queued)]
            with patch.object(sys, "argv", argv), patch.object(mod.time, "time", return_value=100), contextlib.redirect_stdout(io.StringIO()):
                mod.main()
            original = queued.read_bytes()
            with patch.object(sys, "argv", argv), patch.object(mod.time, "time", return_value=200), contextlib.redirect_stdout(io.StringIO()):
                mod.main()
            self.assertEqual(queued.read_bytes(), original)
            self.assertEqual(json.loads(original)["timestamp_us"], 100_000_000)
            self.assertEqual(queued.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(queued.parent.glob(".enqueue-*")), [])


if __name__ == "__main__":
    unittest.main()
