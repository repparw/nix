"""Exercise the fleet's thin CI-gated deploy-rs wrapper with fake external commands."""

import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(sys.argv.pop(1)).read_text()
REVISION = "a" * 40
STUB = r'''
import json, os, sys
from pathlib import Path

root = Path(os.environ["FIXTURE"])
name = Path(sys.argv[0]).name
args = sys.argv[1:]
config = json.loads((root / "config").read_text())
revision = config.get("revision", "a" * 40)
with (root / "calls").open("a") as log:
    log.write(json.dumps([name, *args]) + "\n")

if name == "nix":
    if config.get("metadata_error"):
        sys.exit(1)
    print(json.dumps({"revision": revision, "locked": {"rev": revision}}))
elif name == "curl":
    if config.get("api_error"):
        sys.exit(22)
    print(json.dumps(config["ci"]))
elif name == "deploy":
    if config.get("native_build_failure"):
        print("error: remote derivation build failed", file=sys.stderr)
        sys.exit(1)
    if config.get("native_activation_failure"):
        print("error: activation failed", file=sys.stderr)
        sys.exit(1)
    targets = args[args.index("--targets") + 1:args.index("--skip-checks")]
    hosts = [target.split("#")[-1] for target in targets if "#" in target]
    if not hosts:
        hosts = ["alpha", "epsilon", "pi"]
    for host in hosts:
        (root / host).write_text("new")
elif name == "ssh":
    index = next(i for i, arg in enumerate(args) if arg.startswith("root@"))
    host = args[index].removeprefix("root@")
    command = args[index + 1:]
    if command[:2] == ["readlink", "/run/current-system"]:
        status = (root / host).read_text() if (root / host).exists() else "old"
        print(f"/nix/store/{host}-{status}")
    elif command[:2] == ["nvd", "diff"]:
        print("[U.]  #01  mesa  26.2.2 -> 26.2.4")
'''


def run(revision=REVISION, status="completed", conclusion="success", **fields):
    return dict(run_number=1, head_sha=revision, head_branch="main",
                event="push", status=status, conclusion=conclusion) | fields


class Deployment(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.state = self.root / "state"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        stub = self.bin / "stub"
        stub.write_text(f"#!{sys.executable}\n" + STUB)
        stub.chmod(0o755)
        for name in ("nix", "curl", "deploy", "ssh", "systemctl", "discord-notify"):
            (self.bin / name).symlink_to(stub)
        (self.bin / "python3").symlink_to(sys.executable)
        (self.root / "calls").touch()
        self.script = self.root / "fleet-update"
        script = SOURCE.replace("@FLEET_HOST_JSON@", json.dumps(
            {host: host for host in ("alpha", "epsilon", "pi")}
        ))
        script = script.replace("@PACKAGE_EVENT_SCRIPT@",
                                str(Path(__file__).with_name("package-update-event.py")))
        self.script.write_text("set -euo pipefail\n" + script)

    def deploy(self, ci=None, arguments=None, env=None, **config):
        configuration = {"ci": ci if ci is not None else {"workflow_runs": [run()]}} | config
        (self.root / "config").write_text(json.dumps(configuration))
        environment = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "FIXTURE": str(self.root),
            "FLEET_UPDATE_LOCK": str(self.root / "lock"),
            "FLEET_DEPLOY_KEY": str(self.script),
        } | (env or {})
        result = subprocess.run(["bash", str(self.script), "deploy",
                                 "--state", str(self.state), *(arguments or [])],
                                env=environment, text=True, capture_output=True)
        self.calls = [json.loads(line) for line in (self.root / "calls").read_text().splitlines()]
        return result

    def calls_to(self, name):
        return [c for c in self.calls if c[0] == name]

    def test_all_hosts_use_one_native_deploy_without_custom_activation_or_soak(self):
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        native = self.calls_to("deploy")
        self.assertEqual(len(native), 1)
        self.assertEqual(native[0][1:3],
                         ["--targets", f"github:repparw/nix/{REVISION}"])
        self.assertIn("--skip-checks", native[0])
        self.assertEqual(self.calls_to("nix")[0][1:4], ["flake", "metadata", "--json"])
        self.assertIn("--no-progress", native[0])
        self.assertFalse(any("systemctl is-active" in " ".join(c) for c in self.calls))
        self.assertEqual((self.state / "last-attempted-revision").read_text().strip(), REVISION)
        self.assertEqual((self.state / "last-attempt-status").read_text().strip(), "0")
        self.assertEqual({p.name for p in (self.state / "package-events").glob("*.json")},
                         {f"{REVISION}-{host}.json" for host in ("alpha", "epsilon", "pi")})
        self.assertEqual(len([c for c in self.calls_to("systemctl") if
                              "fleet-headless-reboot.service" in c]), 1)

    def test_failed_revision_is_not_retried_automatically(self):
        first = self.deploy(native_build_failure=True)
        self.assertNotEqual(first.returncode, 0)
        self.assertEqual((self.state / "last-attempt-status").read_text().strip(), "1")
        self.assertEqual((self.state / "last-attempted-revision").read_text().strip(), REVISION)
        second = self.deploy(native_build_failure=True)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(len(self.calls_to("deploy")), 1)
        self.assertFalse((self.state / "deployed-revision").exists())
        self.assertFalse((self.state / "PAUSE").exists())

    def test_new_main_commit_is_attempted_after_failure(self):
        self.assertNotEqual(self.deploy(native_build_failure=True).returncode, 0)
        other = "b" * 40
        result = self.deploy(revision=other, ci={"workflow_runs": [run(revision=other)]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls_to("deploy")), 2)
        self.assertEqual((self.state / "last-attempted-revision").read_text().strip(), other)

    def test_explicit_force_retries_same_revision(self):
        self.assertNotEqual(self.deploy(native_activation_failure=True).returncode, 0)
        result = self.deploy(arguments=["--force"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls_to("deploy")), 2)

    def test_selected_host_deploys_only_that_target(self):
        result = self.deploy(arguments=["pi"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls_to("deploy")[0][1:3],
                         ["--targets", f"github:repparw/nix/{REVISION}#pi"])
        self.assertFalse((self.state / "last-attempted-revision").exists())
        self.assertEqual(len(list((self.state / "package-events").glob("*.json"))), 1)

    def test_multiple_positional_hosts_share_one_deploy_invocation(self):
        result = self.deploy(arguments=["epsilon", "alpha"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls_to("deploy")), 1)
        self.assertEqual(self.calls_to("deploy")[0][1:4], [
            "--targets",
            f"github:repparw/nix/{REVISION}#epsilon",
            f"github:repparw/nix/{REVISION}#alpha",
        ])
        self.assertFalse((self.state / "last-attempted-revision").exists())
        self.assertEqual(len(list((self.state / "package-events").glob("*.json"))), 2)

    def test_unknown_or_duplicate_hosts_are_rejected(self):
        for args in (["unknown"], ["pi", "pi"], ["--host", "pi"]):
            with self.subTest(args=args):
                result = self.deploy(arguments=args)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(self.calls_to("deploy"), [])

    def test_lock_prevents_concurrent_deployment(self):
        with (self.root / "lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.deploy()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.calls_to("deploy"), [])
            self.assertFalse((self.state / "last-attempted-revision").exists())


if __name__ == "__main__":
    unittest.main()
