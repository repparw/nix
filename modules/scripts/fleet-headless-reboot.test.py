"""Run the headless reboot sequence against stubbed SSH, systemd and Discord."""

import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest

SOURCE = Path(sys.argv.pop(1)).read_text()
STUB = r'''
import json, os, sys
from pathlib import Path
root = Path(os.environ['FIXTURE'])
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'calls').open('a') as log:
    log.write(json.dumps([name, *args]) + '\n')
config = json.loads((root / 'config').read_text())
state = json.loads((root / 'state').read_text()) if (root / 'state').exists() else {}


def save(**updates):
    state.update(updates)
    (root / 'state').write_text(json.dumps(state))


def predicate(outcome):
    sys.exit(dict(pending=0, clear=1, unknown=2)[outcome])


if name == 'fleet-reboot-required':
    predicate(config.get('pi_state', 'clear'))
elif name == 'ssh':
    index = next(i for i, a in enumerate(args) if a.startswith('root@'))
    command = args[index + 1:]
    if not command:
        sys.exit(99)
    if command[0] == 'fleet-reboot-required':
        # A rebooted epsilon resolves to its staged boot chain again unless
        # the scenario keeps it mismatched to exercise the verify gate.
        if state.get('epsilon_rebooted') and config.get('epsilon_kernel_converges', True):
            predicate('clear')
        predicate(config.get('epsilon_state', 'clear'))
    elif command[:2] == ['cat', '/proc/sys/kernel/random/boot_id']:
        print(state.get('boot_id', 'old-boot-id'))
    elif command[0] == 'systemctl' and 'is-system-running' in command:
        print(config.get('epsilon_system_state', 'running'))
    elif command[0] == 'systemctl' and 'restic-backups-offsite.service' in command:
        print(config.get('epsilon_backups', 'inactive'))
    elif command[0] == 'systemctl' and 'reboot' in command:
        boot_id = state.get('boot_id', 'old-boot-id')
        if config.get('epsilon_converges', True):
            boot_id = 'new-boot-id'
        save(epsilon_rebooted=True, boot_id=boot_id)
    elif command[0] == 'systemctl' and 'is-active' in command:
        sys.exit(0 if config.get('epsilon_health', 'healthy') == 'healthy' else 1)
    else:
        sys.exit(99)
elif name == 'systemctl':
    if args and args[0] == 'is-active':
        print(config.get('pi_backups', 'inactive'))
    elif args and args[0] == 'reboot':
        save(pi_rebooted=True)
    else:
        sys.exit(99)
elif name == 'curl':
    print('200')
elif name in ('discord-notify', 'sleep'):
    pass
else:
    sys.exit(127)
'''


class RebootSequence(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        stub = self.bin / "stub"
        stub.write_text(f"#!{sys.executable}\n" + STUB)
        stub.chmod(0o755)
        for name in ["ssh", "systemctl", "curl", "discord-notify", "sleep", "fleet-reboot-required"]:
            (self.bin / name).symlink_to(stub)
        self.key = self.root / "deploy_key"
        self.key.write_text("fixture")
        self.lock = self.root / "fleet.lock"
        self.script = self.root / "fleet-headless-reboot"
        script = SOURCE
        script = script.replace("@FLEET_EPSILON_ADDRESS@", "epsilon")
        script = script.replace(
            "@FLEET_EPSILON_CONTAINERS@", "container@one.service container@two.service"
        )
        script = script.replace("@FLEET_APEX_URL@", "https://apex.example/")
        script = script.replace("@FLEET_MINIFLUX_HEALTH@", "https://miniflux.example/healthcheck")
        self.script.write_text("set -euo pipefail\n" + script)

    def run_sequence(self, wait_seconds="60", key=None, lock_wait_seconds="3", **config):
        (self.root / "config").write_text(json.dumps(config))
        env = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "FIXTURE": str(self.root),
            "FLEET_UPDATE_LOCK": str(self.lock),
            "FLEET_DEPLOY_KEY": str(key if key is not None else self.key),
            "FLEET_REBOOT_WAIT_SECONDS": wait_seconds,
            "FLEET_REBOOT_LOCK_WAIT_SECONDS": lock_wait_seconds,
        }
        result = subprocess.run(
            ["bash", str(self.script)], env=env, text=True, capture_output=True
        )
        calls = self.root / "calls"
        self.calls = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
        return result

    def remote_reboots(self):
        # The exact subcommand argument, so predicate calls
        # ("fleet-reboot-required") are not mistaken for reboots.
        return [
            c for c in self.calls
            if c[0] == "ssh" and "reboot" in c[1:]
        ]

    def local_reboots(self):
        return [c for c in self.calls if c[0] == "systemctl" and c[1:] == ["reboot", "--no-block"]]

    def notices(self):
        return [c for c in self.calls if c[0] == "discord-notify"]

    def test_converged_fleet_is_a_noop(self):
        result = self.run_sequence(epsilon_state="clear", pi_state="clear")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("both headless hosts already converged", result.stdout)
        self.assertEqual(self.remote_reboots(), [])
        self.assertEqual(self.local_reboots(), [])
        self.assertEqual(self.notices(), [])

    def test_pending_hosts_reboot_epsilon_first_then_pi(self):
        result = self.run_sequence(epsilon_state="pending", pi_state="pending")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.remote_reboots()), 1)
        self.assertEqual(len(self.local_reboots()), 1)
        epsilon_at = self.calls.index(self.remote_reboots()[0])
        pi_at = self.calls.index(self.local_reboots()[0])
        self.assertLess(epsilon_at, pi_at, "epsilon must reboot before pi")
        messages = [c for c in self.notices() if c[1] == "post"]
        self.assertEqual(len(messages), 2)
        self.assertIn("epsilon", messages[0][2])
        self.assertIn("pi", messages[1][2])

    def test_busy_epsilon_backup_defers_the_sequence(self):
        result = self.run_sequence(
            epsilon_state="pending", pi_state="pending", epsilon_backups="active"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("epsilon backup is active; deferring sequence", result.stdout)
        self.assertEqual(self.remote_reboots(), [])
        self.assertEqual(self.local_reboots(), [])
        self.assertEqual(self.notices(), [])

    def test_unknown_epsilon_state_refuses_the_sequence(self):
        result = self.run_sequence(epsilon_state="unknown", pi_state="pending")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("cannot determine epsilon boot state", result.stderr)
        self.assertEqual(self.remote_reboots(), [])
        self.assertEqual(self.local_reboots(), [])

    def test_pi_only_pending_reboots_pi_without_epsilon(self):
        result = self.run_sequence(epsilon_state="clear", pi_state="pending")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("rebooting pi into staged kernel/initrd", result.stdout)
        self.assertEqual(self.remote_reboots(), [])
        self.assertEqual(len(self.local_reboots()), 1)

    def test_busy_pi_backup_defers_only_pi(self):
        result = self.run_sequence(
            epsilon_state="pending", pi_state="pending", pi_backups="active"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pi backup is active; deferring pi reboot", result.stdout)
        self.assertEqual(len(self.remote_reboots()), 1)
        self.assertEqual(self.local_reboots(), [])

    def test_unconverged_kernel_after_reboot_stops_before_pi(self):
        result = self.run_sequence(
            epsilon_state="pending",
            pi_state="pending",
            epsilon_kernel_converges=False,
        )
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("still on a mismatched kernel/initrd", result.stderr)
        self.assertEqual(self.local_reboots(), [])

    def test_unhealthy_epsilon_after_reboot_stops_before_pi(self):
        result = self.run_sequence(
            wait_seconds="1",
            epsilon_state="pending",
            pi_state="pending",
            epsilon_health="unhealthy",
        )
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("did not return healthy after reboot", result.stderr)
        self.assertEqual(self.local_reboots(), [])

    def test_post_deploy_check_waits_for_lock_release(self):
        # Simulate fleet-update holding the lock when it queues the service.
        handle = open(self.lock, "w")
        self.addCleanup(handle.close)
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        released = threading.Event()

        def unlock():
            fcntl.flock(handle, fcntl.LOCK_UN)
            released.set()

        release = threading.Timer(0.2, unlock)
        release.start()
        self.addCleanup(release.join)
        result = self.run_sequence(
            epsilon_state="clear", pi_state="pending", lock_wait_seconds="3"
        )
        release.join()
        self.assertTrue(released.is_set())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.local_reboots()), 1)

    def test_held_fleet_lock_times_out_without_reboot(self):
        handle = open(self.lock, "w")
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        self.addCleanup(handle.close)
        result = self.run_sequence(
            epsilon_state="pending", pi_state="pending", lock_wait_seconds="0"
        )
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("fleet lock not released before timeout", result.stderr)
        self.assertEqual(self.calls, [])

    def test_unreadable_deploy_key_refuses_before_anything_else(self):
        missing = self.root / "missing_key"
        result = self.run_sequence(key=missing, epsilon_state="pending")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("deployment key is not readable", result.stderr)
        self.assertEqual(self.calls, [])


unittest.main()
