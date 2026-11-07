"""Test exit status propagation from the actual claimer shell wrapper."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest

MODULE = Path(__file__).resolve().parents[1] / "free-games-claimer.nix"


def claim_script(state):
    module = MODULE.read_text()
    source = module.split("claimScript = pkgs.writeShellApplication {", 1)[1]
    match = re.search(r"text = ''\n(.*?)\n          '';", source, re.S)
    if not match:
        raise AssertionError("cannot find claimer wrapper shell script")
    script = textwrap.dedent(match.group(1))
    script = script.replace("${lib.escapeShellArg stateDir}", "'" + str(state) + "'")
    script = script.replace("${claimer}", "/dummy/claimer")
    return script


class ClaimExitTest(unittest.TestCase):
    def run_claim(self, epic, gog):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            state = root / "state"
            (state / "logs").mkdir(parents=True)
            mockbin = root / "bin"
            mockbin.mkdir()
            node = mockbin / "node"
            node.write_text(
                "#!/usr/bin/env bash\n"
                "case \"$1\" in\n"
                "  *epic-games.js) echo epic; exit \"$EPIC_EXIT\";;\n"
                "  *gog.js) echo gog; exit \"$GOG_EXIT\";;\n"
                "  *) exit 99;;\n"
                "esac\n"
            )
            node.chmod(0o755)
            for name in ("Xvfb", "x11vnc"):
                path = mockbin / name
                path.write_text("#!/usr/bin/env bash\nexit 99\n")
                path.chmod(0o755)
            env = os.environ | {
                "PATH": str(mockbin) + os.pathsep + os.environ["PATH"],
                "SHOW": "0",
                "EPIC_EXIT": str(epic),
                "GOG_EXIT": str(gog),
            }
            run = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", claim_script(state)],
                env=env, text=True, capture_output=True,
            )
            self.assertEqual((state / "logs" / "epic-games.status").read_text().strip(), str(epic))
            self.assertEqual((state / "logs" / "gog.status").read_text().strip(), str(gog))
            return run

    def test_success(self):
        run = self.run_claim(0, 0)
        self.assertEqual(run.returncode, 0, run.stderr)

    def test_transient_failure_is_preserved(self):
        for epic, gog in [(75, 0), (0, 75), (75, 75)]:
            with self.subTest(epic=epic, gog=gog):
                run = self.run_claim(epic, gog)
                self.assertEqual(run.returncode, 75, run.stderr)

    def test_permanent_failure_takes_precedence(self):
        for epic, gog in [(1, 75), (75, 1), (1, 0), (0, 1)]:
            with self.subTest(epic=epic, gog=gog):
                run = self.run_claim(epic, gog)
                self.assertEqual(run.returncode, 1, run.stderr)


if __name__ == "__main__":
    unittest.main()
