import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const workflow = readFileSync(join(root, '.github/workflows/ci.yml'), 'utf8');
const validation = readFileSync(join(root, '.github/workflows/revision-validation.yml'), 'utf8');
const gate = validation.match(/      - name: Require every validation group[\s\S]*?        run: \|\n([\s\S]*)$/)[1].replace(/^          /gm, '');

test('the aggregate requires three successes and treats the opt-in arm build skip as acceptable', () => {
  for (const checks of ['success', 'failure', 'skipped', 'cancelled', '']) {
    for (const hosts of ['success', 'failure', 'skipped', 'cancelled', '']) {
      for (const persistence of ['success', 'failure', 'skipped', 'cancelled', '']) {
        for (const arm of ['success', 'skipped', 'failure', 'cancelled', '']) {
          const result = spawnSync('bash', ['-e', '-c', gate], {
            env: { ...process.env, CHECKS_RESULT: checks, HOSTS_RESULT: hosts, PERSISTENCE_RESULT: persistence, ARM_RESULT: arm },
          });
          assert.equal(result.status === 0,
            [checks, hosts, persistence].every(value => value === 'success') && (arm === 'success' || arm === 'skipped'));
        }
      }
    }
  }
  assert.match(validation, /gate:\n    if: always\(\)\n    needs: \[checks, host-eval, persistence-vm, arm-authelia-build\]/);
});

test('every checkout job verifies dispatch SHA before checking out the workflow SHA', () => {
  const jobs = validation.split(/^  [a-z-]+:\n/gm).slice(1).filter(job => job.includes('actions/checkout'));
  assert.equal(jobs.length, 4);
  for (const job of jobs) {
    assert.match(job, /if: inputs.expected_sha != ''/);
    assert.match(job, /EXPECTED_SHA: \$\{\{ inputs.expected_sha \}\}/);
    assert.ok(job.indexOf('test "$GITHUB_SHA" = "$EXPECTED_SHA"') < job.indexOf('actions/checkout'));
    assert.match(job, /ref: \$\{\{ github.sha \}\}/);
    const guard = job.match(/run: (test "\$GITHUB_SHA" = "\$EXPECTED_SHA")/)[1];
    for (const expected of ['reviewed-head', 'stale-head', '']) {
      const result = spawnSync('bash', ['-e', '-c', guard], {
        env: { ...process.env, GITHUB_SHA: 'reviewed-head', EXPECTED_SHA: expected },
      });
      assert.equal(result.status === 0, expected === 'reviewed-head');
    }
  }
  assert.match(workflow, /github.event_name == 'pull_request' && github.event.pull_request.number/);
  assert.match(workflow, /uses: \.\/\.github\/workflows\/revision-validation\.yml/);
  assert.match(workflow, /expected_sha: \$\{\{ github\.event_name == 'workflow_dispatch' && inputs\.expected_sha \|\| '' \}\}/);
  assert.match(validation, /workflow_call:/);
  assert.match(validation, /expected_sha:[\s\S]*required: false[\s\S]*type: string/);
  assert.match(workflow, /cancel-in-progress: \$\{\{ github.event_name != 'push' \}\}/);
  assert.match(workflow, /\|\| github.run_id/);
});

function runChecks(names) {
  const directory = mkdtempSync(join(tmpdir(), 'ci-check-test-'));
  try {
    mkdirSync(join(directory, 'bin'));
    const bash = spawnSync('bash', ['-c', 'command -v bash'], { encoding: 'utf8' }).stdout.trim();
    writeFileSync(join(directory, 'bin/nix'), `#!${bash}\necho "$*" >> calls\necho "build output $2"\n[[ "$2" != *broken ]]\n`, { mode: 0o755 });
    const result = spawnSync('bash', [join(root, '.github/scripts/run-checks.sh')], {
      cwd: directory,
      encoding: 'utf8',
      env: { ...process.env, CI_CHECKS: names, GITHUB_STEP_SUMMARY: join(directory, 'summary'), PATH: `${join(directory, 'bin')}:${process.env.PATH}` },
    });
    const read = name => { try { return readFileSync(join(directory, name), 'utf8'); } catch { return ''; } };
    return { ...result, summary: read('summary'), calls: read('calls'), firstLog: read('ci-logs/broken.log'), secondLog: read('ci-logs/good.log') };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test('a failed build remains failed through tee, records evidence and continues later checks', () => {
  const result = runChecks('broken good');
  assert.equal(result.status, 1);
  assert.match(result.firstLog, /build output .#checks.x86_64-linux.broken/);
  assert.match(result.secondLog, /build output .#checks.x86_64-linux.good/);
  assert.match(result.summary, /broken: failure/);
  assert.match(result.summary, /good: success/);
  assert.match(result.stdout, /::error title=broken failed/);
  assert.equal(result.calls.trim().split('\n').length, 2);
  assert.match(result.calls, /--no-update-lock-file --no-link --print-build-logs/);
});

test('all successful checks pass and invalid or empty selections cannot pass silently', () => {
  assert.equal(runChecks('good').status, 0);
  for (const names of ['', '   ', '../bad']) {
    const result = runChecks(names);
    assert.notEqual(result.status, 0);
    assert.equal(result.calls, '');
  }
});
