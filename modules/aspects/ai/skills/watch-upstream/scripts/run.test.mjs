import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join, dirname } from 'node:path';
import { test } from 'node:test';

const runner = resolve(import.meta.dirname, 'run.sh');
const actions = resolve(import.meta.dirname, 'actions.sh');
const source = process.env.AGENT_SKILLS_SOURCE ?? resolve(import.meta.dirname, '../../../../../..');
function command(bin, args, options = {}) {
  const result = spawnSync(bin, args, { encoding: 'utf8', ...options });
  assert.equal(result.status, 0, `${bin} ${args.join(' ')}\n${result.stderr}\n${result.stdout}`);
  return result.stdout.trim();
}
const shell = command('bash', ['-c', 'command -v bash']);
function fixture(t, state = 'waiting-upstream') {
  const dir = mkdtempSync(join(tmpdir(), 'watch-upstream-test.'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const remote = join(dir, 'origin.git'), repo = join(dir, 'repo'), bin = join(dir, 'bin'), log = join(dir, 'events');
  const env = { ...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null', GIT_AUTHOR_NAME: 'Watcher test', GIT_AUTHOR_EMAIL: 'test@example.invalid', GIT_COMMITTER_NAME: 'Watcher test', GIT_COMMITTER_EMAIL: 'test@example.invalid', TEST_EVENTS: log, TEST_STATE: state, TEST_NEXT_STATE: 'adopting', PATH: `${bin}:${process.env.PATH}` };
  mkdirSync(bin);
  const git = (...args) => command('git', args, { cwd: repo, env });
  command('git', ['init', '--bare', '--initial-branch=main', remote], { env });
  command('git', ['clone', remote, repo], { env });
  function put(path, body) { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, body.replace('#!/usr/bin/env bash', `#!${shell}`), { mode: 0o755 }); }
  put(join(repo, 'data/upstream-gates.json'), JSON.stringify({ schema: 1, gates: { demo: { input: 'nixpkgs', watcher: 'watch-demo.timer', issue: 'https://example.invalid/issues/1', workaround: ['workaround.nix'] } } }));
  put(join(repo, 'flake.lock'), 'original\n');
  put(join(repo, 'workaround.nix'), 'workaround\n');
  put(join(repo, 'unrelated.txt'), 'keep\n');
  put(join(repo, 'modules/scripts/upstream-gates.sh'), `#!/usr/bin/env bash
set -euo pipefail
printf 'check\\n' >> "$TEST_EVENTS"
[[ -z \${TEST_CHECK_FAIL:-} ]] || exit 23
state=$TEST_STATE
if grep -q updated flake.lock; then state=$TEST_NEXT_STATE; fi
jq -cn --arg state "$state" '{id:"demo",status:$state}'
`);
  const adapter = join(dir, 'actions.sh');
  put(adapter, `#!/usr/bin/env bash
set -euo pipefail
case "$2" in
 completed) [[ -z \${TEST_COMPLETION_ERROR:-} ]] || exit 2; [[ ! -e workaround.nix ]] ;;
 apply) printf 'apply\\n' >> "$TEST_EVENTS"; rm workaround.nix
   if [[ -n \${TEST_UNOWNED:-} ]]; then echo changed > unrelated.txt; git add unrelated.txt; fi ;;
 verify) printf 'verify\\n' >> "$TEST_EVENTS"; [[ -z \${TEST_VERIFY_FAIL:-} ]] || exit 31 ;;
esac
`);
  put(join(bin, 'nix'), `#!/usr/bin/env bash
set -euo pipefail
printf 'nix %s\\n' "$*" >> "$TEST_EVENTS"
[[ "$*" == 'flake update nixpkgs' ]]
printf 'updated\\n' > flake.lock
`);
  put(join(bin, 'gh'), `#!/usr/bin/env bash
set -euo pipefail
printf 'close\\n' >> "$TEST_EVENTS"
[[ -z \${TEST_CLOSE_FAIL:-} ]] || exit 19
`);
  put(join(bin, 'systemctl'), `#!/usr/bin/env bash
printf 'disarm %s\\n' "$*" >> "$TEST_EVENTS"
`);
  git('add', '.'); git('commit', '-m', 'fixture'); git('push', 'origin', 'main');
  const original = git('rev-parse', 'HEAD');
  writeFileSync(join(repo, 'workaround.nix'), 'dirty local content\n');
  const run = (extra = {}, flags = []) => spawnSync('bash', [runner, ...flags, repo, 'demo', adapter], { cwd: dir, env: { ...env, ...extra }, encoding: 'utf8' });
  const events = () => existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n') : [];
  const remoteHead = () => command('git', ['--git-dir', remote, 'rev-parse', 'main'], { env });
  return { dir, repo, remote, env, git, original, run, events, remoteHead, log };
}

for (const state of ['waiting-upstream', 'waiting-unstable']) {
  test(`${state} is quiet and leaves a dirty checkout and origin untouched`, t => {
    const f = fixture(t, state), result = f.run();
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, `demo: ${state}\n`);
    assert.deepEqual(f.events(), ['check']);
    assert.equal(f.remoteHead(), f.original);
    assert.equal(readFileSync(join(f.repo, 'workaround.nix'), 'utf8'), 'dirty local content\n');
    assert.equal(f.git('worktree', 'list', '--porcelain').match(/^worktree /gm).length, 1);
  });
}
test('waiting-pin updates the declared input, rechecks, validates, pushes, closes, then disarms', t => {
  const f = fixture(t, 'waiting-pin'), result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(f.events(), ['check', 'nix flake update nixpkgs', 'check', 'apply', 'verify', 'close', 'disarm --user disable --now watch-demo.timer']);
  assert.notEqual(f.remoteHead(), f.original);
  assert.equal(command('git', ['--git-dir', f.remote, 'show', 'main:flake.lock']), 'updated');
  assert.equal(readFileSync(join(f.repo, 'flake.lock'), 'utf8'), 'original\n');
  assert.equal(readFileSync(join(f.repo, 'workaround.nix'), 'utf8'), 'dirty local content\n');
  writeFileSync(f.log, '');
  const again = f.run();
  assert.equal(again.status, 0, again.stderr);
  assert.deepEqual(f.events(), ['close', 'disarm --user disable --now watch-demo.timer']);
});
test('adopting performs cleanup without an input update', t => {
  const f = fixture(t, 'adopting'), result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(f.events(), ['check', 'apply', 'verify', 'close', 'disarm --user disable --now watch-demo.timer']);
});
test('a pin still waiting after an update does not trigger cleanup', t => {
  const f = fixture(t, 'waiting-pin'), result = f.run({ TEST_NEXT_STATE: 'waiting-pin' });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(f.events(), ['check', 'nix flake update nixpkgs', 'check']);
  assert.equal(f.remoteHead(), f.original);
});
for (const state of ['waiting-pin', 'adopting']) {
  test(`check-only reports ${state} without updating, cleaning up, closing, or disarming`, t => {
    const f = fixture(t, state), result = f.run({}, ['--check-only']);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, `demo: ${state}\n`);
    assert.deepEqual(f.events(), ['check']);
    assert.equal(f.remoteHead(), f.original);
  });
}
for (const [name, extra] of [
  ['checker error', { TEST_CHECK_FAIL: '1' }],
  ['invalid checker response', { TEST_STATE: 'unexpected' }],
  ['completion-check error', { TEST_COMPLETION_ERROR: '1' }],
  ['validation failure', { TEST_VERIFY_FAIL: '1' }],
  ['unowned staged write', { TEST_UNOWNED: '1' }],
]) {
  test(`${name} leaves origin unchanged and the timer armed`, t => {
    const f = fixture(t, 'adopting'), result = f.run(extra);
    assert.notEqual(result.status, 0);
    assert.equal(f.remoteHead(), f.original);
    assert.ok(!f.events().includes('close'));
    assert.ok(!f.events().some(event => event.startsWith('disarm')));
  });
}
test('a rejected push can retry from fresh origin without losing local edits', t => {
  const f = fixture(t, 'adopting');
  const hook = join(f.remote, 'hooks/pre-receive');
  writeFileSync(hook, `#!${shell}\nexit 1\n`, { mode: 0o755 });
  assert.notEqual(f.run().status, 0);
  assert.equal(f.remoteHead(), f.original);
  assert.ok(!f.events().includes('close'));
  rmSync(hook);
  const retry = f.run();
  assert.equal(retry.status, 0, retry.stderr);
  assert.notEqual(f.remoteHead(), f.original);
  assert.equal(readFileSync(join(f.repo, 'workaround.nix'), 'utf8'), 'dirty local content\n');
});
test('an issue-close failure retries completion without applying the cleanup again', t => {
  const f = fixture(t, 'adopting');
  assert.notEqual(f.run({ TEST_CLOSE_FAIL: '1' }).status, 0);
  const adopted = f.remoteHead();
  assert.notEqual(adopted, f.original);
  assert.ok(!f.events().some(event => event.startsWith('disarm')));
  writeFileSync(f.log, '');
  assert.equal(f.run().status, 0);
  assert.equal(f.remoteHead(), adopted);
  assert.deepEqual(f.events(), ['close', 'disarm --user disable --now watch-demo.timer']);
});

const registry = JSON.parse(readFileSync(join(source, 'data/upstream-gates.json'), 'utf8'));
for (const [gate, spec] of Object.entries(registry.gates)) {
  test(`current ${gate} cleanup removes its workaround and preserves valid Nix`, t => {
    const dir = mkdtempSync(join(tmpdir(), 'watch-action-test.'));
    t.after(() => rmSync(dir, { recursive: true, force: true }));
    const paths = [...new Set([...spec.workaround, 'modules/aspects/ai/default.nix', 'modules/entities.nix'])];
    for (const path of paths) {
      mkdirSync(dirname(join(dir, path)), { recursive: true });
      if (existsSync(join(source, path))) writeFileSync(join(dir, path), readFileSync(join(source, path)));
    }
    command('git', ['init', '--initial-branch=main', dir]);
    command('git', ['add', '.'], { cwd: dir });
    command('git', ['-c', 'user.name=Watcher test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'fixture'], { cwd: dir });
    const before = spawnSync('bash', [actions, gate, 'completed'], { cwd: dir }).status;
    if (before === 0) {
      t.skip('Cleanup already adopted; retire this gate and its actions.');
      return;
    }
    assert.equal(before, 1);
    command('bash', [actions, gate, 'apply'], { cwd: dir });
    assert.equal(spawnSync('bash', [actions, gate, 'completed'], { cwd: dir }).status, 0);
    for (const path of paths.filter(p => p.endsWith('.nix') && existsSync(join(dir, p)))) {
      command('nix-instantiate', ['--parse', join(dir, path)]);
    }
    if (gate === 'qbittorrent-pr-24055') assert.match(readFileSync(join(dir, 'modules/aspects/services/arr.nix'), 'utf8'), /services\.qbittorrent\.group = "media"/);
    if (gate.startsWith('home-manager-9842') || gate === 'cliamp-attach-453') assert.match(readFileSync(join(dir, 'modules/aspects/cliamp.nix'), 'utf8'), /programs\.cliamp/);
  });
}

test('installing twice replaces every registered launcher and preserves the original backup', t => {
  const dir = mkdtempSync(join(tmpdir(), 'watch-install-test.'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const bin = join(dir, 'bin');
  mkdirSync(bin);
  writeFileSync(join(bin, 'watch-qbittorrent.sh'), 'legacy watcher\n');
  const installer = resolve(import.meta.dirname, 'install.sh');
  command('bash', [installer, source, bin]);
  const first = readFileSync(join(bin, 'watch-qbittorrent.sh'), 'utf8');
  command('bash', [installer, source, bin]);
  assert.equal(readFileSync(join(bin, 'watch-qbittorrent.sh'), 'utf8'), first);
  for (const spec of Object.values(registry.gates)) {
    command('bash', ['-n', join(bin, spec.watcher.replace(/\.timer$/, '.sh'))]);
  }
  const backup = command('find', [join(dir, 'lib'), '-path', '*/previous/watch-qbittorrent.sh']);
  assert.equal(readFileSync(backup, 'utf8'), 'legacy watcher\n');
});

test('source-fetch failures are checker errors, not an ordinary waiting state', t => {
  const dir = mkdtempSync(join(tmpdir(), 'watch-checker-test.'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'bin'));
  writeFileSync(join(dir, 'bin/curl'), `#!${shell}\nexit 22\n`, { mode: 0o755 });
  writeFileSync(join(dir, 'flake.lock'), JSON.stringify({ nodes: { root: { inputs: { nixpkgs: 'nixpkgs' } }, nixpkgs: { locked: { rev: 'pinned' } } } }));
  for (const kind of ['file-contains', 'package-version']) {
    const gate = { input: 'nixpkgs', repository: 'example/repo', branch: 'main', source: { kind: 'none' }, channel: { kind, path: 'module.nix', text: 'ready', minimum: '1.0' }, pin: { kind, path: 'module.nix', text: 'ready', minimum: '1.0' }, workaround: [], completion: 'done', watcher: 'watch-demo.timer', issue: null, upstream: [] };
    const registryPath = join(dir, 'registry.json');
    writeFileSync(registryPath, JSON.stringify({ schema: 1, gates: { demo: gate } }));
    const result = spawnSync('bash', [join(source, 'modules/scripts/upstream-gates.sh'), 'check', 'demo', '--json'], {
      encoding: 'utf8', cwd: dir,
      env: { ...process.env, PATH: `${dir}/bin:${process.env.PATH}`, UPSTREAM_GATES_REGISTRY: registryPath, UPSTREAM_GATES_REPO: dir },
    });
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /demo\terror/);
  }
});
