import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const workflow = readFileSync(join(root, '.github/workflows/main-packages.yml'), 'utf8');
const smokeWorkflow = readFileSync(join(root, '.github/workflows/package-prebuild-smoke.yml'), 'utf8');

test('main package builds use pinned native tooling and skip cached targets', () => {
  assert.match(workflow, /branches: \[main\]/);
  assert.doesNotMatch(workflow, /pull_request|system\.build\.toplevel|--cachix-cache/);
  assert.match(workflow, /--flake "\.#ciPackages\.\$SYSTEM"/);
  assert.match(workflow, /--skip-cached/);
  assert.match(workflow, /runner: ubuntu-24.04-arm/);
  assert.match(workflow, /runner: ubuntu-24.04\n/);
  assert.match(workflow, /cancel-in-progress: false/);
  assert.match(workflow, /test "\$GITHUB_SHA" = "\$EXPECTED_SHA"/);
  assert.match(workflow, /test -s ci-logs\/packages\.json/);
  assert.match(workflow, /hashFiles\('ci-logs\/packages\.json'\)/);
});

test('PR smoke tests both native systems and avoids cache publishing credentials', () => {
  assert.match(smokeWorkflow, /pull_request:/);
  assert.match(smokeWorkflow, /ciPackageSmoke\.\$SYSTEM/);
  assert.match(smokeWorkflow, /--skip-cached/);
  assert.match(smokeWorkflow, /runner: ubuntu-24\.04-arm/);
  assert.match(smokeWorkflow, /nix-store --query --requisites/);
  assert.match(smokeWorkflow, /publish-main-packages\.sh/);
  assert.doesNotMatch(smokeWorkflow, /secrets\.CACHIX_AUTH_TOKEN/);
});

function publish({ failure = '', malformed = false, manifest = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'main-packages-test-'));
  try {
    mkdirSync(join(dir, 'bin'));
    mkdirSync(join(dir, 'ci-logs'));
    const result = (type, cacheStatus, path) => ({ type, cacheStatus, success: true, outputs: { out: path } });
    if (manifest) writeFileSync(join(dir, 'ci-logs/packages.json'), malformed ? '{' : JSON.stringify({ results: [
      result('BUILD', undefined, '/nix/store/safe'),
      result('BUILD', undefined, '/nix/store/system'),
      result('EVAL', 'cached', '/nix/store/remote'),
      result('EVAL', 'local', '/nix/store/local'),
    ] }));
    const bash = spawnSync('bash', ['-c', 'command -v bash'], { encoding: 'utf8' }).stdout.trim();
    writeFileSync(join(dir, 'bin/nix-store'), `#!${bash}
[[ "$FAILURE" != query ]] || exit 1
echo "$3"
[[ "$3" != /nix/store/system ]] || echo /nix/store/vault.sops.yaml
exit 0
`, { mode: 0o755 });
    writeFileSync(join(dir, 'bin/cachix'), `#!${bash}
echo "$*" >> calls
[[ "$FAILURE" != upload ]]
`, { mode: 0o755 });
    const run = spawnSync('bash', [join(root, '.github/scripts/publish-main-packages.sh')], {
      cwd: dir, encoding: 'utf8', env: { ...process.env, FAILURE: failure,
        CACHIX_AUTH_TOKEN: 'test-token', PATH: `${join(dir, 'bin')}:${process.env.PATH}` },
    });
    let calls = '';
    try { calls = readFileSync(join(dir, 'calls'), 'utf8'); } catch {}
    return { ...run, calls };
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

test('publishing only sends local successful outputs with vault-free closures', () => {
  const run = publish();
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.calls.trim(), 'push repparw /nix/store/local /nix/store/safe');
  assert.doesNotMatch(run.stdout + run.stderr, /test-token/);
});

test('invalid results, failed closure inspection and upload errors fail publishing', () => {
  assert.notEqual(publish({ malformed: true }).status, 0);
  assert.equal(publish({ failure: 'query' }).calls, '');
  assert.notEqual(publish({ failure: 'query' }).status, 0);
  assert.notEqual(publish({ failure: 'upload' }).status, 0);
});

test('a missing manifest fails rather than silently skipping publication', () => {
  const run = publish({ manifest: false });
  assert.notEqual(run.status, 0);
  assert.equal(run.calls, '');
});
