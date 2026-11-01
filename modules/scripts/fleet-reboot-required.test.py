"""Run the reboot predicate against fixture boot/staged directory trees."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(sys.argv.pop(1)).read_text()


class RebootRequired(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.booted = self.root / "booted"
        self.staged = self.root / "staged"
        self.store = self.root / "store"
        self.store.mkdir()
        self.staged.mkdir()
        for name in ["initrd", "kernel", "kernel-modules"]:
            (self.store / name).touch()

    def link_booted(self):
        self.booted.mkdir()
        for name in ["initrd", "kernel", "kernel-modules"]:
            (self.booted / name).symlink_to(self.store / name)

    def link_staged(self):
        for name in ["initrd", "kernel", "kernel-modules"]:
            (self.staged / name).symlink_to(self.store / name)

    def run_predicate(self):
        script = self.root / "fleet-reboot-required"
        script.write_text(SOURCE)
        result = subprocess.run(
            [
                "bash",
                str(script),
                "--booted",
                str(self.booted),
                "--staged",
                str(self.staged),
            ],
            capture_output=True,
            text=True,
        )
        return result

    def test_matching_targets_are_converged(self):
        self.link_booted()
        self.link_staged()
        result = self.run_predicate()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stderr, "")

    def test_differing_kernel_target_is_pending(self):
        self.link_booted()
        self.link_staged()
        replacement = self.store / "kernel-next"
        replacement.touch()
        (self.staged / "kernel").unlink()
        (self.staged / "kernel").symlink_to(replacement)
        self.assertEqual(self.run_predicate().returncode, 0)

    def test_regular_file_instead_of_shared_target_is_pending(self):
        # A plain file resolves to its own path, never to the running
        # kernel's store path, so the boot chain is not the staged one.
        self.link_booted()
        self.link_staged()
        (self.staged / "kernel").unlink()
        (self.staged / "kernel").touch()
        self.assertEqual(self.run_predicate().returncode, 0)

    def test_resolved_target_matters_not_link_path(self):
        self.link_booted()
        self.link_staged()
        (self.staged / "kernel-modules").unlink()
        (self.staged / "kernel-modules").symlink_to(self.booted / "kernel-modules")
        self.assertEqual(self.run_predicate().returncode, 1)

    def test_missing_staged_link_is_unknown(self):
        self.link_booted()
        self.assertEqual(self.run_predicate().returncode, 2)
        self.assertIn("missing", self.run_predicate().stderr)

    def test_missing_booted_tree_is_unknown(self):
        self.link_staged()
        self.assertEqual(self.run_predicate().returncode, 2)

    def test_broken_symlink_is_unknown(self):
        self.link_booted()
        self.link_staged()
        (self.staged / "initrd").unlink()
        (self.staged / "initrd").symlink_to(self.store / "gone")
        self.assertEqual(self.run_predicate().returncode, 2)

    def test_usage_contract(self):
        script = self.root / "fleet-reboot-required"
        script.write_text(SOURCE)
        help_result = subprocess.run(
            ["bash", str(script), "--help"], capture_output=True, text=True
        )
        self.assertEqual(help_result.returncode, 0)
        self.assertIn("usage:", help_result.stdout)
        bad_result = subprocess.run(
            ["bash", str(script), "--nope"], capture_output=True, text=True
        )
        self.assertEqual(bad_result.returncode, 2)
        self.assertIn("usage:", bad_result.stderr)


unittest.main()
