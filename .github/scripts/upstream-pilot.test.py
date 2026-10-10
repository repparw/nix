#!/usr/bin/env python3
"""Run the real pilot against isolated Git repositories and a fake GitHub API."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PYTHON = __import__('sys').executable


class Pilot(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.repo = self.directory / 'repo'
        self.remote = self.directory / 'remote.git'
        subprocess.run(['git', 'init', '--bare', str(self.remote)], check=True, capture_output=True)
        subprocess.run(['git', 'clone', str(self.remote), str(self.repo)], check=True, capture_output=True)
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.test')
        self.git('switch', '-c', 'main')
        (self.repo / 'modules/_services').mkdir(parents=True)
        shutil.copy(ROOT / '.github/upstream/fixtures/authelia-before.nix.txt', self.repo / 'modules/_services/authelia.nix')
        shutil.copy(ROOT / 'flake.lock', self.repo / 'flake.lock')
        self.git('add', '.')
        self.git('commit', '-m', 'fixture base')
        self.git('push', '-u', 'origin', 'main')
        self.script = self.directory / 'pilot.sh'
        shutil.copy(ROOT / '.github/scripts/upstream-watch.sh', self.script)
        self.bin = self.directory / 'bin'
        self.bin.mkdir()
        (self.bin / 'python3').write_text('#!/bin/sh\nprintf "{}\\n"\n')
        (self.bin / 'python3').chmod(0o755)
        gh = self.bin / 'gh'
        gh.write_text('#!' + PYTHON + '\n' + r'''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
state = Path(os.environ['FIXTURE_STATE'])
with (state/'calls').open('a') as log: log.write(json.dumps(args)+'\n')
mode = os.environ.get('FIXTURE_MODE', '')
if args[0] == 'api':
    endpoint = args[1]
    if mode == 'api-error': sys.exit(1)
    if '/pulls/' in endpoint: print(json.dumps({'merged': mode != 'upstream-open'}))
    elif '/compare/' in endpoint:
        merge = endpoint.split('/compare/')[1].split('...')[0]
        print(json.dumps({'status': 'behind' if mode == 'pin-behind' else 'ahead', 'merge_base_commit': {'sha': merge}}))
    else: print(json.dumps({'sha': 'channel-sha'}))
elif args[:2] == ['pr', 'list']:
    print('500' if (state/'pr').exists() else '')
elif args[:2] == ['pr', 'create']:
    (state/'pr').touch(); print('https://github.com/repparw/nix/pull/500')
elif args[:2] == ['run', 'list']:
    print(json.dumps([{'status': 'completed', 'conclusion': 'failure' if mode == 'ci-failed' else 'success'}]))
elif args[:2] == ['workflow', 'run']:
    pass
else: sys.exit(2)
''')
        gh.chmod(0o755)
        self.env = {**os.environ, 'PATH': str(self.bin) + ':' + os.environ['PATH'], 'FIXTURE_STATE': str(self.directory), 'GITHUB_REPOSITORY': 'repparw/nix', 'GITHUB_STEP_SUMMARY': str(self.directory/'summary'), 'GIT_CONFIG_GLOBAL': '/dev/null'}

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo, text=True, stderr=subprocess.DEVNULL).strip()

    def run_pilot(self, mode=''):
        return subprocess.run(['bash', str(self.script)], cwd=self.repo, env={**self.env, 'FIXTURE_MODE': mode}, text=True, capture_output=True)

    def calls(self):
        return [json.loads(line) for line in (self.directory/'calls').read_text().splitlines()]

    def test_ready_create_dispatch_reuse_merge_complete(self):
        first = self.run_pilot()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertIn('CI dispatched', first.stdout)
        candidate = self.git('rev-parse', 'HEAD')
        self.assertEqual(self.git('diff', '--name-only', 'main', 'HEAD'), 'modules/_services/authelia.nix')
        self.assertNotIn('autheliaPackage', (self.repo/'modules/_services/authelia.nix').read_text())
        self.git('switch', 'main')
        second = self.run_pilot()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn('waiting-merge', second.stdout)
        self.assertEqual(self.git('rev-parse', 'fix/authelia-drop-pnpm-hash-override'), candidate)
        dispatches = [call for call in self.calls() if call[:2] == ['workflow', 'run']]
        self.assertEqual(len(dispatches), 1)
        self.assertIn('expected_sha='+candidate, dispatches[0])
        self.assertIn('build_arm_authelia=true', dispatches[0])
        self.git('merge', '--ff-only', candidate)
        complete = self.run_pilot()
        self.assertEqual(complete.returncode, 0, complete.stderr)
        self.assertIn('already done', complete.stdout)
        self.assertEqual(len([call for call in self.calls() if call[:2] == ['workflow', 'run']]), 1)

    def test_failed_candidate_ci_stays_pending_without_overwrite(self):
        self.assertEqual(self.run_pilot().returncode, 0)
        candidate = self.git('rev-parse', 'HEAD')
        self.git('switch', 'main')
        failed = self.run_pilot('ci-failed')
        self.assertEqual(failed.returncode, 0, failed.stderr)
        self.assertIn('CI failure', failed.stdout)
        self.assertEqual(self.git('rev-parse', 'fix/authelia-drop-pnpm-hash-override'), candidate)
        self.assertEqual(len([call for call in self.calls() if call[:2] == ['workflow', 'run']]), 1)

    def test_waiting_and_unavailable_never_publish(self):
        for mode in ('upstream-open', 'pin-behind', 'api-error'):
            with self.subTest(mode=mode):
                result = self.run_pilot(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse((self.directory/'pr').exists())
                self.assertEqual(self.git('branch', '--list', 'fix/authelia-drop-pnpm-hash-override'), '')

    def test_orphan_branch_is_never_overwritten(self):
        self.git('push', 'origin', 'main:refs/heads/fix/authelia-drop-pnpm-hash-override')
        result = self.run_pilot()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('refusing to overwrite', result.stderr)
        self.assertFalse((self.directory/'pr').exists())


if __name__ == '__main__':
    unittest.main()
