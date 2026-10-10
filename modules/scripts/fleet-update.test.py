"""Run the deployment entry point against fake GitHub, Nix and SSH endpoints."""

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
root = Path(os.environ['FIXTURE'])
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'calls').open('a') as log:
    log.write(json.dumps([name, *args]) + '\n')
config = json.loads((root / 'config').read_text())
revision = 'a' * 40
if name == 'git':
    if 'rev-parse' in args:
        print('false' if '--is-shallow-repository' in args else revision)
    elif 'push' in args or 'revert' in args or 'commit' in args:
        sys.exit(99)
elif name == 'df':
    print('Filesystem 1K-blocks Used Available Use% Mounted\nfixture 90000000 1 80000000 1% /nix')
elif name == 'curl':
    if any('api.github.com' in a for a in args):
        if config.get('api_error'):
            sys.exit(22)
        print(json.dumps(config['ci']))
    else:
        print('200')
elif name == 'nix':
    if args[0] == 'build' and config.get('schema_failure'):
        print('error: invalid deployment schema', file=sys.stderr)
        sys.exit(1)
    if args[0] == 'eval':
        target = ' '.join(args)
        if 'builtins.getFlake' in target and config.get('eval_failure') and config['eval_failure'] in target:
            print('error: host evaluation failed', file=sys.stderr)
            sys.exit(1)
        if 'currentSystem' in target:
            print('x86_64-linux')
        elif 'containerUnits' in target and 'builtins.getFlake' not in target:
            print('[]')
        elif 'activityGate' in target and 'builtins.getFlake' not in target:
            print('true' if config.get('busy_alpha') and '.alpha.' in target else 'false')
        elif 'builtins.getFlake' in target:
            host = next(h for h in ['epsilon', 'alpha', 'pi'] if f'nixosConfigurations.{h}.' in target)
            print(json.dumps(dict(revision=revision,
                systemPath='invalid-path' if config.get('invalid_metadata') == host else f'/nix/store/{host}-system-26.11',
                activityGate=bool(config.get('busy_alpha') and host == 'alpha'), containerUnits=[],
                deployment=dict(remoteBuild=True, nodes={host: dict(hostname=host,
                    profiles=dict(system=dict(path=f'/nix/store/{host}-profile-26.11',
                                              drvPath=f'/nix/store/{host}-profile-26.11.drv', user='root')))}))))
elif name == 'deploy':
    host = args[0].split('#')[-1]
    (root / host).write_text('new')
    if config.get('deploy_failure') == host:
        print('error: activation connection lost', file=sys.stderr)
        sys.exit(1)
elif name == 'ssh':
    index = next(i for i, a in enumerate(args) if a.startswith('root@'))
    host = args[index].removeprefix('root@')
    command = args[index + 1:]
    current = (root / host).read_text() if (root / host).exists() else 'old'
    if command[0].endswith('/sw/bin/nixos-version'):
        print('c' * 40 if config.get('inconsistent_revision') == host else revision)
    elif command[0] == 'nix' and command[1] == 'build':
        if config.get('prepare_failure') == host:
            print('error: preparation build failed', file=sys.stderr)
            sys.exit(1)
        print(f'/nix/store/{host}-profile-26.11')
    elif command[0] == 'nixos-version':
        print(revision if current == 'new' else 'b' * 40)
    elif command[0] == 'nix' and command[1] == 'store':
        print("mesa: 26.2.2 ⟶ 26.2.4, 2.1 MiB")
    elif command[0] == 'readlink':
        print(f'/nix/store/{host}-{current}')
    elif command[0] == 'systemctl' and command[1] == 'is-system-running':
        print('running')
    elif command[0] == 'systemctl' and config.get('unhealthy') == host:
        sys.exit(1)
    elif command[0] == 'systemd-inhibit':
        print('[{"mode":"block","what":"sleep","who":"fixture"}]')
    elif command[0].endswith('/bin/switch-to-configuration'):
        if config.get('rollback_failure') == host:
            sys.exit(1)
        (root / host).write_text('old')
    elif 'hermes-package-ingest' in command[0]:
        if config.get('hermes_down'):
            sys.exit(255)
        payload = json.loads(sys.stdin.read())
        with (root / "received").open("a") as received:
            received.write(json.dumps(payload) + "\n")
        print(json.dumps({"event_id": "wrong" if config.get("wrong_ack") else payload["event_id"]}))
'''


def run(number=1, status="completed", conclusion="success", **fields):
    return dict(run_number=number, head_sha=REVISION, head_branch="main", event="push",
                status=status, conclusion=conclusion) | fields


class Deployment(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.state = self.root / "state"
        (self.state / "src" / ".git").mkdir(parents=True)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        stub = self.bin / "stub"
        stub.write_text(f"#!{sys.executable}\n" + STUB)
        stub.chmod(0o755)
        for name in ["git", "df", "curl", "nix", "deploy", "ssh", "sleep"]:
            (self.bin / name).symlink_to(stub)
        (self.bin / "python3").symlink_to(sys.executable)
        self.script = self.root / "fleet-update"
        script = SOURCE.replace("/run/secrets/hermes-env", str(self.root / "missing-secret"))
        for host in ["alpha", "pi", "epsilon"]:
            script = script.replace(f"@FLEET_{host.upper()}_ADDRESS@", host)
        script = script.replace("@PACKAGE_EVENT_SCRIPT@", str(Path(__file__).with_name("package-update-event.py")))
        self.script.write_text("set -euo pipefail\n" + script)

    def deploy(self, ci=None, arguments=None, **config):
        (self.root / "config").write_text(json.dumps(dict(ci=ci or {"workflow_runs": [run()]}) | config))
        env = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "FIXTURE": str(self.root),
            "FLEET_UPDATE_LOCK": str(self.root / "lock"),
            "FLEET_UPDATE_ROOTS": str(self.root / "roots"),
            "FLEET_DEPLOY_KEY": str(self.script),
            "FLEET_SOAK_ATTEMPTS": "2",
        }
        result = subprocess.run(["bash", str(self.script), "deploy", "--state", str(self.state),
                                 *(arguments or [])], env=env, text=True, capture_output=True)
        self.assertTrue((self.root / "calls").exists(), result.stdout + result.stderr)
        self.calls = [json.loads(line) for line in (self.root / "calls").read_text().splitlines()]
        return result

    def assert_no_activation(self):
        self.assertFalse(any(c[0] in ["deploy", "ssh"] for c in self.calls))
        self.assertFalse((self.state / "PAUSE").exists())
        self.assertFalse((self.state / "rollback-streak").exists())

    def test_ci_missing_pending_failed_wrong_sha_and_pr_do_not_activate(self):
        fixtures = [[], [run(status="in_progress", conclusion=None)], [run(conclusion="failure")],
                    [run(head_sha="c" * 40)], [run(event="pull_request")], [run(event="schedule")],
                    [run(event="workflow_dispatch", head_branch="feature")],
                    [run(head_branch="automation/flake-lock")],
                    [run(), run(2, status="queued", conclusion=None)]]
        for runs in fixtures:
            with self.subTest(runs=runs):
                result = self.deploy(ci={"workflow_runs": runs})
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assert_no_activation()

    def test_api_failure_does_not_activate(self):
        self.assertNotEqual(self.deploy(api_error=True).returncode, 0)
        self.assert_no_activation()

    def test_exact_main_workflow_dispatch_allows_deploy(self):
        result = self.deploy(ci={"workflow_runs": [run(event="workflow_dispatch")]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c[1].split('#')[-1] for c in self.calls if c[0] == "deploy"],
                         ["epsilon", "alpha", "pi"])

    def test_exact_lock_candidate_dispatch_allows_deploy_after_fast_forward(self):
        result = self.deploy(ci={"workflow_runs": [
            run(event="workflow_dispatch", head_branch="automation/flake-lock")
        ]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c[1].split('#')[-1] for c in self.calls if c[0] == "deploy"],
                         ["epsilon", "alpha", "pi"])

    def test_all_hosts_converge_after_ci(self):
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c[1].split('#')[-1] for c in self.calls if c[0] == "deploy"], ["epsilon", "alpha", "pi"])
        first_activation = next(i for i, c in enumerate(self.calls) if c[0] == 'deploy')
        prepared = [c for c in self.calls[:first_activation] if c[0] == 'ssh' and 'build' in c]
        self.assertEqual(len(prepared), 3)
        evidence = Path((self.state / 'latest-preparation').read_text().strip())
        results = [json.loads(p.read_text()) for p in evidence.glob('result-*.json')]
        self.assertEqual({r['host'] for r in results}, {'epsilon', 'alpha', 'pi'})
        self.assertTrue(all(r['revision'] == REVISION and r['outcome'] == 'prepared' for r in results))
        self.assertEqual((self.state / "deployed-revision").read_text().strip(), REVISION)
        self.assertEqual(list(self.state.glob("reached-*")), [])
        self.assertFalse(any(c[0] == "git" and c[1] in ["push", "revert", "commit"] for c in self.calls))

    def test_force_still_requires_ci(self):
        result = self.deploy(ci={"workflow_runs": []}, arguments=["--host", "alpha", "--force"])
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_activation()

    def test_explicit_forced_fleet_deploy_preserves_pause(self):
        pause = self.state / "PAUSE"
        pause.write_text("existing operator pause\n")
        result = self.deploy(arguments=["--host", "all", "--force"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(pause.read_text(), "existing operator pause\n")
        self.assertEqual((self.state / "deployed-revision").read_text().strip(), REVISION)
        self.assertEqual([c[1].split('#')[-1] for c in self.calls if c[0] == "deploy"], ["epsilon", "alpha", "pi"])

    def test_force_requires_explicit_host_selection(self):
        result = subprocess.run(["bash", str(self.script), "deploy", "--force"],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("explicit --host", result.stderr)

    def test_preflight_failure_on_first_host_cannot_be_hidden_by_later_hosts(self):
        result = self.deploy(eval_failure="epsilon")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_activation()
        self.assertIn("host evaluation failed", (self.state / "preflight.log").read_text())
        evidence = Path((self.state / 'latest-preparation').read_text().strip())
        results = {p.stem.removeprefix('result-'): json.loads(p.read_text())
                   for p in evidence.glob('result-*.json')}
        self.assertEqual(results, {
            'epsilon': dict(host='epsilon', revision=REVISION, systemPath=None,
                            profilePath=None, outcome='failed', stage='capture'),
            'alpha': dict(host='alpha', revision=REVISION, systemPath=None,
                          profilePath=None, outcome='not_attempted'),
            'pi': dict(host='pi', revision=REVISION, systemPath=None,
                       profilePath=None, outcome='not_attempted'),
        })
        self.assertIn('host evaluation failed', (evidence / 'capture-epsilon.log').read_text())

    def test_invalid_captured_metadata_records_failure_and_unattempted_hosts(self):
        result = self.deploy(invalid_metadata='alpha')
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_activation()
        evidence = Path((self.state / 'latest-preparation').read_text().strip())
        self.assertEqual(json.loads((evidence / 'result-alpha.json').read_text()),
                         dict(host='alpha', revision=REVISION, systemPath=None,
                              profilePath=None, outcome='failed', stage='capture'))
        self.assertEqual(json.loads((evidence / 'result-pi.json').read_text()),
                         dict(host='pi', revision=REVISION, systemPath=None,
                              profilePath=None, outcome='not_attempted'))
        self.assertEqual(json.loads((evidence / 'result-epsilon.json').read_text()),
                         dict(host='epsilon', revision=REVISION,
                              systemPath='/nix/store/epsilon-system-26.11',
                              profilePath='/nix/store/epsilon-profile-26.11', outcome='not_attempted'))
        self.assertEqual(json.loads((evidence / 'alpha.json').read_text())['systemPath'], 'invalid-path')
        self.assertIn('captured metadata for alpha is invalid', (evidence / 'capture-alpha.log').read_text())
        self.assertFalse((evidence / 'capture-pi.log').exists())

    def test_capture_failure_records_only_selected_host_and_preserves_prior_evidence(self):
        previous = self.state / 'preparation-prior'
        previous.mkdir()
        prior_files = {previous / f'result-{host}.json': json.dumps(dict(host=host, outcome='prepared'))
                       for host in ['epsilon', 'alpha', 'pi']}
        for path, contents in prior_files.items():
            path.write_text(contents)
        result = self.deploy(eval_failure='alpha', arguments=['--host', 'alpha'])
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_activation()
        evidence = Path((self.state / 'latest-preparation').read_text().strip())
        self.assertEqual([p.name for p in evidence.glob('result-*.json')], ['result-alpha.json'])
        self.assertEqual(json.loads((evidence / 'result-alpha.json').read_text())['outcome'], 'failed')
        for path, contents in prior_files.items():
            self.assertEqual(path.read_text(), contents)

    def test_schema_failure_does_not_activate(self):
        self.assertNotEqual(self.deploy(schema_failure=True).returncode, 0)
        self.assert_no_activation()

    def test_failed_activation_restores_failed_host_and_previous_hosts(self):
        result = self.deploy(deploy_failure="pi")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / "pi").read_text(), "old")
        self.assertEqual((self.root / "alpha").read_text(), "old")
        self.assertEqual((self.root / "epsilon").read_text(), "old")
        self.assertTrue((self.state / "PAUSE").exists())
        self.assertFalse(any(c[0] == "git" and c[1] in ["push", "revert", "commit"] for c in self.calls))

    def test_failed_alpha_prevents_controller_activation(self):
        result = self.deploy(deploy_failure="alpha")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([c[1].split('#')[-1] for c in self.calls if c[0] == "deploy"], ["epsilon", "alpha"])
        self.assertFalse((self.root / "pi").exists())

    def test_failed_rollback_keeps_roots_and_pauses(self):
        result = self.deploy(deploy_failure="pi", rollback_failure="pi")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.state / "PAUSE").exists())
        self.assertFalse(any(c[0] == "ssh" and "rm" in c for c in self.calls))

    def test_retry_rolls_back_hosts_reached_during_earlier_deferred_run(self):
        result = self.deploy(busy_alpha=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.state / "deployed-revision").exists())
        self.assertEqual((self.root / "epsilon").read_text(), "new")
        result = self.deploy(deploy_failure="alpha", arguments=["--host", "alpha"])
        self.assertNotEqual(result.returncode, 0)
        for host in ["epsilon", "pi", "alpha"]:
            self.assertEqual((self.root / host).read_text(), "old")

    def test_already_running_revision_must_pass_health(self):
        (self.root / "epsilon").write_text("new")
        result = self.deploy(unhealthy="epsilon")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.state / "deployed-revision").exists())
        self.assertFalse(any(c[0] == "deploy" for c in self.calls))

    def test_failed_preparation_stops_before_any_activation(self):
        result = self.deploy(prepare_failure='alpha')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[0] == 'deploy' for c in self.calls))
        self.assertFalse(any(c[0] == 'ssh' and 'switch-to-configuration' in ' '.join(c) for c in self.calls))
        self.assertTrue((self.state / 'PAUSE').exists())
        self.assertEqual(list(self.state.glob('reached-*')), [])
        evidence = Path((self.state / 'latest-preparation').read_text().strip())
        self.assertIn('preparation build failed', (evidence / 'prepare-alpha.log').read_text())
        self.assertEqual(json.loads((evidence / 'result-alpha.json').read_text())['outcome'], 'failed')

    def ingested(self):
        return [c for c in self.calls if c[0] == "ssh" and "hermes-package-ingest" in " ".join(c)]

    def outbox(self):
        directory = self.state / "package-events"
        return sorted(directory.glob("*.json")) if directory.exists() else []

    def deliver(self, **config):
        (self.root / "config").write_text(json.dumps(config))
        script = self.root / "deliver"
        source = Path(__file__).with_name("package-update-deliver.sh").read_text().replace("@FLEET_EPSILON_ADDRESS@", "epsilon")
        script.write_text("set -euo pipefail\n" + source)
        env = os.environ | {"PATH": f"{self.bin}:{os.environ['PATH']}", "FIXTURE": str(self.root), "FLEET_UPDATE_STATE": str(self.state), "FLEET_DEPLOY_KEY": str(self.script)}
        result = subprocess.run(["bash", str(script)], env=env, text=True, capture_output=True)
        self.calls = [json.loads(line) for line in (self.root / "calls").read_text().splitlines()]
        return result

    def test_full_convergence_enqueues_before_cleanup_without_transport(self):
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.outbox()), 3)
        self.assertEqual(self.ingested(), [])
        self.assertEqual(list(self.state.glob("reached-*")), [])
        self.assertEqual({json.loads(path.read_text())["host"] for path in self.outbox()}, {"alpha", "pi", "epsilon"})
        self.assertEqual(self.deliver().returncode, 0)
        self.assertEqual(len(self.ingested()), 3)
        self.assertEqual(self.outbox(), [])

    def test_deferred_convergence_queues_only_reached_hosts(self):
        result = self.deploy(busy_alpha=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({json.loads(path.read_text())["host"] for path in self.outbox()}, {"pi", "epsilon"})
        self.assertEqual(self.ingested(), [])

    def test_intake_unavailability_retains_exact_bytes_for_independent_retry(self):
        self.assertEqual(self.deploy().returncode, 0)
        before = {path.name: path.read_bytes() for path in self.outbox()}
        self.assertEqual(self.deliver(hermes_down=True).returncode, 0)
        self.assertEqual(before, {path.name: path.read_bytes() for path in self.outbox()})
        self.assertEqual(self.deliver().returncode, 0)
        self.assertEqual(self.outbox(), [])
        received = [json.loads(line) for line in (self.root / "received").read_text().splitlines()]
        self.assertEqual(sorted(received, key=lambda event: event["host"]), sorted([json.loads(value) for value in before.values()], key=lambda event: event["host"]))

    def test_wrong_ack_retains_events(self):
        self.assertEqual(self.deploy().returncode, 0)
        self.assertEqual(self.deliver(wrong_ack=True).returncode, 0)
        self.assertEqual(len(self.outbox()), 3)

    def test_pending_events_retry_without_deploy_even_when_paused(self):
        self.assertEqual(self.deploy().returncode, 0)
        (self.state / "PAUSE").touch()
        (self.root / "calls").unlink()
        self.assertEqual(self.deliver().returncode, 0)
        self.assertEqual(self.outbox(), [])
        self.assertEqual(len(self.ingested()), 3)
        self.assertFalse(any(call[0] in ("git", "nix", "deploy") for call in self.calls))

    def test_inconsistent_prepared_revision_stops_before_any_activation(self):
        result = self.deploy(inconsistent_revision='pi')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[0] == 'deploy' for c in self.calls))
        evidence = Path((self.state / 'latest-preparation').read_text().strip())
        self.assertEqual(json.loads((evidence / 'result-pi.json').read_text())['revision'], 'c' * 40)
        self.assertIn('expected ' + REVISION, (evidence / 'prepare-pi.log').read_text())


if __name__ == "__main__":
    unittest.main()
