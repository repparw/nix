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
            "[U.]  #01  mesa  26.2.2 -> 26.2.4",
            "[U.]  #02  irrelevant-other  1.0 -> 2.0",
        ))
        self.assertEqual(packages, [{"name": "mesa", "from": "26.2.2", "to": "26.2.4"}])

    def test_multi_output_versions_kept_verbatim(self):
        packages = mod.parse_diff(transitions(
            "[U*]  #03  mesa  2.1.6, 2.1.6-drivers, 2.1.6-man -> 2.1.8, 2.1.8-drivers, 2.1.8-man",
        ))
        self.assertEqual(packages, [{
            "name": "mesa",
            "from": "2.1.6, 2.1.6-drivers, 2.1.6-man",
            "to": "2.1.8, 2.1.8-drivers, 2.1.8-man",
        }])

    def test_added_and_removed_sections_skipped(self):
        packages = mod.parse_diff(transitions(
            "Version changes:",
            "Added packages:",
            "[A.]  #1  avantreeStable.conf  <none>",
            "Removed packages:",
            "[R.]  #1  activatable-nixos-system-alpha  26.11.20261010.6510408",
            "Closure size: 3387 -> 3382 (416 paths added, 421 paths removed, delta -5, disk usage -482.1MiB).",
        ))
        self.assertEqual(packages, [])

    def test_none_only_transition_skipped(self):
        packages = mod.parse_diff(transitions(
            "[C.]  #09  opencode  <none> -> <none>",
        ))
        self.assertEqual(packages, [])

    def test_none_version_maps_to_empty(self):
        packages = mod.parse_diff(transitions(
            "[U.]  #05  moonshine  <none> -> 0.16.1",
        ))
        self.assertEqual(packages, [{"name": "moonshine", "from": "", "to": "0.16.1"}])

    def test_prefix_matches_and_others_do_not(self):
        packages = mod.parse_diff(transitions(
            "[U.]  #01  nix-2.31  2.31.0 -> 2.31.1",
            "[U.]  #02  nixos-system-alpha  26.11.a -> 26.11.b",
        ))
        self.assertEqual([p["name"] for p in packages], ["nix-2.31"])

    def test_kernel_and_nix_names_match_without_matching_nixos(self):
        packages = mod.parse_diff(transitions(
            "[U.]  #01  linux  6.16 -> 6.17",
            "[U.]  #02  nix  2.31 -> 2.32",
            "[U.]  #03  nixos-system-alpha  old -> new",
        ))
        self.assertEqual([item["name"] for item in packages], ["linux", "nix"])

    def test_cap_at_32_packages(self):
        lines = [f"[U.]  #{i:02d}  mesa-pkg{i}  1 -> 2" for i in range(40)]
        self.assertEqual(len(mod.parse_diff(transitions(*lines))), 32)

    def test_real_alpha_deploy_diff(self):
        # Verbatim shape from the 2026-10-14 alpha deploy; nothing in that
        # particular diff hits the triage tiers, so nothing is extracted.
        diff = transitions(
            "<<< /nix/var/nix/profiles/system-2785-link",
            ">>> /run/current-system",
            "Version changes:",
            "[U.]  #07  nixos-system-alpha  26.11.20261010.6510408, "
            "26.11.20261010.6510408-activate-path, 26.11.20261010.6510408-activate-rs "
            "-> 26.11.20261011.7fd4004",
            "[U.]  #13  typescript-language-server  5.3.0 -> 6.0.2",
            "Added packages:",
            "[A.]  #2  ps-procps  4.0.7",
            "Removed packages:",
            "[R.]  #2  deploy-rs  0-unstable-2026-09-14",
            "Closure size: 3387 -> 3382 (416 paths added, 421 paths removed, delta -5, disk usage -482.1MiB).",
        )
        self.assertEqual(mod.parse_diff(diff), [])

    def test_real_alpha_deploy_diff_extracts_triaged(self):
        # Same diff shape with a triaged package present.
        diff = transitions(
            "Version changes:",
            "[U.]  #07  nixos-system-alpha  old -> new",
            "[U.]  #14  steam  1.0.80 -> 1.0.81",
            "Closure size: 3387 -> 3382 (delta -5).",
        )
        self.assertEqual(mod.parse_diff(diff), [
            {"name": "steam", "from": "1.0.80", "to": "1.0.81"},
        ])


class EventTests(unittest.TestCase):
    def test_event_shape_and_deterministic_id(self):
        diff = transitions("[U.]  #01  mesa  26.2.2 -> 26.2.4")
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
            diff.write_text("[U.]  #01  mesa  26.2.2 -> 26.2.4\n")
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
