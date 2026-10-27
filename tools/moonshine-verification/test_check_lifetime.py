import pathlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("check-lifetime.py")


class LifetimeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.start = pathlib.Path(self.temp.name) / "start"

    def check(self, container, runner, now=10000):
        if container is not None:
            self.start.write_text(str(container))
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--container-start-file", str(self.start),
             "--runner-start-us", str(runner), "--now", str(now)],
            capture_output=True, text=True,
        )

    def test_full_budget_and_boundary_are_accepted(self):
        self.assertEqual(self.check(9900, 9_900_000_000).returncode, 0)
        self.assertEqual(self.check(9460, 9_760_000_000).returncode, 0)

    def test_late_dispatch_is_rejected_for_either_service(self):
        self.assertEqual(self.check(9459, 9_900_000_000).returncode, 1)
        self.assertEqual(self.check(9900, 9_759_000_000).returncode, 1)

    def test_missing_malformed_and_future_timestamps_fail_closed(self):
        self.assertEqual(self.check(None, 9_900_000_000).returncode, 2)
        self.assertEqual(self.check("bad", 9_900_000_000).returncode, 2)
        self.assertEqual(self.check(9900, "bad").returncode, 2)
        self.assertEqual(self.check(10001, 9_900_000_000).returncode, 2)
        self.assertEqual(self.check(9900, 10_001_000_000).returncode, 2)


if __name__ == "__main__":
    unittest.main()
