import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { classifyChanges } from './ci-impact.mjs';

const root = resolve(import.meta.dirname, '../..');
const workflow = readFileSync(join(root, '.github/workflows/ci.yml'), 'utf8');
const validation = readFileSync(join(root, '.github/workflows/revision-validation.yml'), 'utf8');
const upstreamWatch = readFileSync(join(root, '.github/workflows/upstream-watch.yml'), 'utf8');
const gate = validation.match(/      - name: Require every validation group[\s\S]*?        run: \|\n([\s\S]*)$/)[1].replace(/^          /gm, '');

test('the aggregate respects only classifier-authorized skips', () => {
  const runGate = (overrides = {}) => spawnSync('bash', ['-e', '-c', gate], {
    env: {
      ...process.env,
      CHANGES_RESULT: 'success',
      CHECKS_RESULT: 'success',
      NEOVIM_ENABLED: 'true',
      NEOVIM_RESULT: 'success',
      HOSTS_RESULT: 'success',
      PERSISTENCE_RESULT: 'success',
      HOSTS_ENABLED: 'true',
      PERSISTENCE_ENABLED: 'true',
      UPSTREAM_WATCHER: '',
      UPSTREAM_RESULT: 'skipped',
      ...overrides,
    },
  }).status === 0;
  assert.equal(runGate(), true);
  assert.equal(runGate({ NEOVIM_ENABLED: 'false', NEOVIM_RESULT: 'skipped' }), true);
  assert.equal(runGate({ HOSTS_ENABLED: 'false', HOSTS_RESULT: 'skipped', PERSISTENCE_ENABLED: 'false', PERSISTENCE_RESULT: 'skipped' }), true);
  assert.equal(runGate({ PERSISTENCE_ENABLED: 'false', PERSISTENCE_RESULT: 'skipped' }), true);
  assert.equal(runGate({ UPSTREAM_WATCHER: 'tasks-org', UPSTREAM_RESULT: 'success' }), true);
  for (const env of [
    { CHANGES_RESULT: 'failure' }, { CHECKS_RESULT: 'failure' },
    ...['failure', 'cancelled', 'skipped'].map(NEOVIM_RESULT => ({ NEOVIM_RESULT })),
    { NEOVIM_ENABLED: 'false', NEOVIM_RESULT: 'success' },
    { NEOVIM_ENABLED: 'unknown' },
    { HOSTS_ENABLED: 'true', HOSTS_RESULT: 'skipped' },
    { HOSTS_ENABLED: 'false', HOSTS_RESULT: 'success' },
    { HOSTS_ENABLED: 'unknown' },
    { PERSISTENCE_ENABLED: 'true', PERSISTENCE_RESULT: 'skipped' },
    { PERSISTENCE_ENABLED: 'false', PERSISTENCE_RESULT: 'success' },
    { PERSISTENCE_ENABLED: 'unknown' },
    { UPSTREAM_WATCHER: 'tasks-org', UPSTREAM_RESULT: 'skipped' },
    { UPSTREAM_WATCHER: 'tasks-org', UPSTREAM_RESULT: 'failure' },
    { UPSTREAM_RESULT: 'failure' },
  ]) assert.equal(runGate(env), false, JSON.stringify(env));
  assert.match(validation, /gate:\n    if: always\(\)\n    needs: \[changes, checks, neovim-build, host-eval, persistence-vm, upstream-package-build\]/);
  assert.match(validation, /matrix: \$\{\{ fromJSON\(needs.changes.outputs.check_matrix\) \}\}/);
  assert.match(validation, /if: needs.changes.outputs.run_persistence_vm == 'true'/);
});

test('every checkout job verifies dispatch SHA before checking out the workflow SHA', () => {
  const jobs = validation.split(/^  [a-z-]+:\n/gm).slice(1).filter(job => job.includes('actions/checkout'));
  assert.equal(jobs.length, 6);
  for (const job of jobs) {
    assert.match(job, /if: inputs.expected_sha != ''/);
    assert.match(job, /EXPECTED_SHA: \$\{\{ inputs.expected_sha \}\}/);
    assert.ok(job.indexOf('test "$GITHUB_SHA" = "$EXPECTED_SHA"') < job.indexOf('actions/checkout'));
    assert.match(job, /ref: \$\{\{ (github.event.pull_request.head.sha \|\| )?github.sha \}\}/);
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

test('all host evaluations share one runner, and failed lock updates do not wake the watcher', () => {
  assert.match(validation, /name: host-eval \(fleet, stubbed\)/);
  assert.match(validation, /CI_CHECKS: alpha pi epsilon/);
  assert.doesNotMatch(validation, /matrix:\\n        host: \[alpha, pi, epsilon\]/);
  assert.match(upstreamWatch, /if: github.event_name != 'workflow_run' \|\| github.event.workflow_run.conclusion == 'success'/);
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


test('docs-only PRs skip the workflow watcher tests but code changes retain them', () => {
  const watcherGroup = validation.match(/name: Test upstream watcher predicates and pilot lifecycle\n\s+if: matrix.group == '([^']+)'/)[1];
  const runsWatcher = paths => classifyChanges(paths).checkMatrix.include.some(g => g.group === watcherGroup);
  assert.equal(runsWatcher(['docs/hosts.md', 'README.md']), false);
  for (const path of ['.github/scripts/upstream-plan.py', '.github/workflows/revision-validation.yml', 'flake.lock']) {
    assert.equal(runsWatcher([path]), true, path);
  }
});

test('atomic package validation reads the PR head and includes bundled ARM validation', () => {
  const job = validation.split('  upstream-package-build:')[1].split('\n  gate:')[0];
  assert.match(job, /ref: \$\{\{ github.event.pull_request.head.sha \|\| github.sha \}\}/);
  assert.match(job, /contains\(inputs.upstream_watcher, 't3code-split'\) \|\| inputs.upstream_watcher == 'automation\/atomic-cleanup'/);
  assert.match(job, /"architecture":"arm","runner":"ubuntu-24.04-arm"/);
  const script = job.split('        run: |\n')[1].replace(/^          /gm, '');
  const directory = mkdtempSync(join(tmpdir(), 'atomic-package-test-'));
  try {
    const run = (cmd, args) => {
      const result = spawnSync(cmd, args, { cwd: directory, encoding: 'utf8' });
      assert.equal(result.status, 0, result.stderr);
      return result.stdout.trim();
    };
    run('git', ['init', '-b', 'main']);
    run('git', ['config', 'user.name', 'fixture']);
    run('git', ['config', 'user.email', 'fixture@example.test']);
    run('git', ['commit', '--allow-empty', '-m', 'base']);
    run('git', ['switch', '-c', 'candidate']);
    run('git', ['commit', '--allow-empty', '-m', 'fix(upstream): updated lock (authelia-pnpm-hash,t3code-split,qbittorrent)']);
    const head = run('git', ['rev-parse', 'HEAD']);
    run('git', ['switch', 'main']);
    run('git', ['merge', '--no-ff', 'candidate', '-m', 'Merge candidate into main']);
    mkdirSync(join(directory, 'bin'));
    const bash = spawnSync('bash', ['-c', 'command -v bash'], { encoding: 'utf8' }).stdout.trim();
    writeFileSync(join(directory, 'bin/python3'), `#!${bash}\nprintf '%s\\n' "$*" >> calls\n`, { mode: 0o755 });
    const validate = architecture => spawnSync('bash', ['-euo', 'pipefail', '-c', script], {
      cwd: directory, encoding: 'utf8',
      env: { ...process.env, PATH: `${join(directory, 'bin')}:${process.env.PATH}`, WATCHERS: 'automation/atomic-cleanup', ARCHITECTURE: architecture },
    });
    assert.notEqual(validate('x86').status, 0, 'a synthetic merge message must fail closed');
    run('git', ['checkout', '--detach', head]);
    assert.equal(validate('x86').status, 0);
    assert.equal(validate('arm').status, 0);
    assert.deepEqual(readFileSync(join(directory, 'calls'), 'utf8').trim().split('\n'), [
      '.github/scripts/upstream-validate.py t3code-split --architecture x86',
      '.github/scripts/upstream-validate.py qbittorrent --architecture x86',
      '.github/scripts/upstream-validate.py t3code-split --architecture arm',
    ]);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('only trusted revisions publish, with an explicitly forwarded step-scoped key', () => {
  assert.match(workflow, /secrets:\n      CACHIX_SIGNING_KEY: \$\{\{ secrets.CACHIX_SIGNING_KEY \}\}/);
  assert.doesNotMatch(workflow, /secrets: inherit/);
  assert.match(workflow, /CACHIX_AUTH_TOKEN: \$\{\{ secrets.CACHIX_AUTH_TOKEN \}\}/);
  assert.match(validation, /CACHIX_AUTH_TOKEN:\n        required: false/);
  assert.match(validation, /workflow_call:\n    secrets:\n      CACHIX_SIGNING_KEY:\n        required: false/);
  const job = validation.split('  neovim-build:')[1].split('\n  persistence-vm:')[0];
  const publish = job.split('      - name: Publish and verify the Neovim closure')[1].split('      - name: Upload build logs')[0];
  const condition = publish.match(/if: (.*)/)[1];
  const allowed = new Function('github', `return ${condition}`);
  for (const [event, actor, source, expected] of [
    ['push', 'repparw', undefined, true],
    ['workflow_dispatch', 'repparw', undefined, true],
    ['pull_request', 'repparw', 'repparw/nix', true],
    ['pull_request', 'contributor', 'contributor/nix', false],
    ['pull_request', 'dependabot[bot]', 'repparw/nix', false],
  ]) {
    assert.equal(allowed({ actor, event_name: event, repository: 'repparw/nix',
      event: { pull_request: source ? { head: { repo: { full_name: source } } } : undefined } }), expected);
  }
  const beforePublish = job.split('      - name: Publish and verify the Neovim closure')[0];
  assert.doesNotMatch(beforePublish, /signingKey:|CACHIX_SIGNING_KEY:|CACHIX_AUTH_TOKEN:/);
  const preflight = beforePublish.split('      - name: Require trusted publishing credentials')[1].split('      - name: Build')[0];
  assert.equal(preflight.match(/if: (.*)/)[1], condition);
  assert.match(preflight, /secrets.CACHIX_SIGNING_KEY != '' && secrets.CACHIX_AUTH_TOKEN != ''/);
  const preflightScript = preflight.split('        run: |\n')[1].replace(/^          /gm, '');
  for (const present of ['true', 'false', '']) {
    const result = spawnSync('bash', ['-e', '-c', preflightScript], {
      env: { ...process.env, CACHIX_CREDENTIALS_PRESENT: present },
    });
    assert.equal(result.status === 0, present === 'true');
  }
  assert.match(beforePublish, /skipPush: true/);
  assert.match(publish, /CACHIX_SIGNING_KEY: \$\{\{ secrets.CACHIX_SIGNING_KEY \}\}/);
  assert.match(publish, /CACHIX_AUTH_TOKEN: \$\{\{ secrets.CACHIX_AUTH_TOKEN \}\}/);
  assert.match(publish, /run: bash .github\/scripts\/publish-neovim.sh/);
});

function publishNeovim(fail = '', key = 'fixture-not-a-secret', token = 'fixture-not-a-token') {
  const directory = mkdtempSync(join(tmpdir(), 'publish-neovim-test-'));
  try {
    mkdirSync(join(directory, 'bin'));
    const bash = spawnSync('bash', ['-c', 'command -v bash'], { encoding: 'utf8' }).stdout.trim();
    const mock = `#!${bash}
set -euo pipefail
command_name="$(basename "$0")"
printf '%s %s\\n' "$command_name" "$*" >> calls
case "$command_name $*" in
  'nix path-info .#'*) stage=local; echo /nix/store/fixture-nixvim ;;
  'cachix push '*) stage=upload ;;
  'nix path-info --store '*) stage=remote; echo /nix/store/fixture-nixvim ;;
  'nix store verify '*) stage=signature ;;
  *) exit 90 ;;
esac
[[ "$stage" != "$FAIL_STAGE" ]]
`;
    for (const command of ['nix', 'cachix']) writeFileSync(join(directory, 'bin', command), mock, { mode: 0o755 });
    const result = spawnSync('bash', [join(root, '.github/scripts/publish-neovim.sh')], {
      cwd: directory, encoding: 'utf8',
      env: { ...process.env, PATH: `${join(directory, 'bin')}:${process.env.PATH}`,
        CACHIX_SIGNING_KEY: key, CACHIX_AUTH_TOKEN: token, FAIL_STAGE: fail, GITHUB_STEP_SUMMARY: join(directory, 'summary') },
    });
    const read = name => { try { return readFileSync(join(directory, name), 'utf8'); } catch { return ''; } };
    return { ...result, calls: read('calls'), summary: read('summary'), paths: read('ci-logs/host-neovim-paths') };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test('publishing waits for upload and verifies remote availability and signatures without building', () => {
  const result = publishNeovim();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.calls, /cachix push repparw \/nix\/store\/fixture-nixvim/);
  assert.match(result.calls, /nix path-info --store https:\/\/repparw.cachix.org --recursive/);
  assert.match(result.calls, /nix store verify .*--no-contents --sigs-needed 1 .*--option trusted-public-keys repparw.cachix.org-1:/);
  assert.doesNotMatch(result.calls, /nix build|--rebuild/);
  assert.match(result.paths, /fixture-nixvim/);
  assert.match(result.summary, /fixture-nixvim/);
  assert.doesNotMatch(result.stdout + result.stderr + result.summary, /fixture-not-a-secret|fixture-not-a-token/);
});

test('missing credentials, uploads, remote paths and signatures cannot silently pass', () => {
  const missing = publishNeovim('', '');
  assert.notEqual(missing.status, 0);
  assert.equal(missing.calls, '');
  const missingToken = publishNeovim('', 'fixture-not-a-secret', '');
  assert.notEqual(missingToken.status, 0);
  assert.equal(missingToken.calls, '');
  for (const failure of ['local', 'upload', 'remote', 'signature']) {
    const result = publishNeovim(failure);
    assert.notEqual(result.status, 0, failure);
    assert.equal(result.summary, '', failure);
    if (failure === 'upload') assert.doesNotMatch(result.calls, /nix path-info --store/);
  }
});
