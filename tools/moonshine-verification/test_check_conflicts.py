import pathlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("check-conflicts.py")


class HostConflictTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.proc = pathlib.Path(self.temp.name)
        self.process(1, "systemd")

    def process(self, pid, comm, group="/user.slice/desktop", args=()):
        directory = self.proc / str(pid)
        directory.mkdir()
        (directory / "comm").write_text(comm + "\n")
        (directory / "cgroup").write_text(f"0::{group}\n")
        (directory / "cmdline").write_bytes(b"\0".join(s.encode() for s in args) + b"\0")

    def check(self):
        return subprocess.run([sys.executable, str(SCRIPT), "--proc", str(self.proc)], capture_output=True, text=True)

    def test_desktop_activity_is_allowed(self):
        self.process(10, "firefox")
        self.process(11, "niri")
        self.assertEqual(self.check().returncode, 0)

    def test_stream_game_and_other_verification_are_refused(self):
        for comm, group, args in [
            ("niri", "/system.slice/moonshine-session.service", ()),
            ("gamescope", "/user.slice/desktop", ()),
            ("moonshine-bench", "/user.slice/desktop", ()),
            ("python3", "/user.slice/desktop", ("python3", "tools/verification/verify_video.py", "smoke")),
        ]:
            with self.subTest(comm=comm):
                self.process(10, comm, group, args)
                self.assertEqual(self.check().returncode, 1)
                for path in (self.proc / "10").iterdir():
                    path.unlink()
                (self.proc / "10").rmdir()

    def test_missing_host_proc_fails_closed(self):
        (self.proc / "1" / "cgroup").unlink()
        self.assertEqual(self.check().returncode, 2)


if __name__ == "__main__":
    unittest.main()
