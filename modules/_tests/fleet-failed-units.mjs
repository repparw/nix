import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const probe = process.env.FLEET_HEALTH_PROBE;
const source = process.env.FLEET_UNIT_SOURCE;
function fixture() {
  const root = mkdtempSync(join(tmpdir(), 'fleet-units-'));
  const probeBody = join(root, 'probe.sh');
  writeFileSync(probeBody, readFileSync(probe, 'utf8').replace(/^export PATH=.*\n/m, ''));
  const bin = join(root, 'bin');
  const state = join(root, 'state');
  const evidence = join(root, 'evidence');
  mkdirSync(bin); mkdirSync(state); mkdirSync(evidence);
  const env = { ...process.env, PATH: `${bin}:${process.env.PATH}`, HOSTNAME: 'pi', STATE_DIRECTORY: state,
    FLEET_UNIT_STATE_DIRECTORY: evidence, MOCK_ROOT: root };
  function mock(name, body) { writeFileSync(join(bin, name), `#!${process.env.TEST_BASH || '/usr/bin/env bash'}\nset -euo pipefail\n${body}\n`, { mode: 0o755 }); }
  mock('systemctl', `case "$1" in
    is-active) exit 0;;
    is-failed) echo inactive; exit 0;;
    list-units) [ ! -f "$MOCK_ROOT/list-error" ]; cat "$MOCK_ROOT/live";;
    *) exit 2;; esac`);
  mock('curl', 'printf 200');
  mock('fleet-unit-snapshot', '[ ! -f "$MOCK_ROOT/pi-error" ]; cat "$MOCK_ROOT/pi"');
  mock('ssh', `for arg in "$@"; do case "$arg" in root@*) target="$arg";; esac; done
    case "$target" in root@192.168.0.18) host=alpha;; *) host=epsilon;; esac
    [ ! -f "$MOCK_ROOT/$host-error" ]; cat "$MOCK_ROOT/$host"`);
  mock('discord-notify', `printf '%s|%s\n' "$1" "$2" >> "$MOCK_ROOT/messages"
    [ ! -f "$MOCK_ROOT/$1-error" ]
    if [ "$1" = post ]; then echo "id-$(wc -l < "$MOCK_ROOT/messages")"; fi`);
  for (const host of ['pi', 'alpha', 'epsilon', 'live']) writeFileSync(join(root, host), '');
  function run(script, args = [], extra = {}) {
    return spawnSync('bash', ['-euo', 'pipefail', script, ...args], { env: { ...env, ...extra }, encoding: 'utf8' });
  }
  function sweep(args = []) { const r = run(probeBody, args); assert.equal(r.status, 0, r.stderr); }
  function messages() { return existsSync(join(root, 'messages')) ? readFileSync(join(root, 'messages'), 'utf8') : ''; }
  return { root, state, evidence, run, sweep, messages, set: (name, text) => writeFileSync(join(root, name), text), cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

test('same unit on separate hosts alerts after two detections and recovers independently', () => {
  const f = fixture(); try {
    f.set('alpha', 'backup.service\n'); f.set('epsilon', 'backup.service\n');
    f.sweep(); assert.equal(f.messages(), '');
    f.sweep(); assert.match(f.messages(), /DOWN pi unit-failed:alpha:backup.service/);
    assert.match(f.messages(), /DOWN pi unit-failed:epsilon:backup.service/);
    f.set('alpha', ''); f.sweep();
    assert.equal(existsSync(join(f.state, '.unit-failed:alpha:backup.service.msgid')), false);
    assert.equal(existsSync(join(f.state, '.unit-failed:epsilon:backup.service.msgid')), true);
    assert.equal(f.messages().split('\n').filter(s => s.startsWith('post|')).length, 2);
  } finally { f.cleanup(); }
});

test('unreachable host alerts without clearing retained unit state; healthy reconnection clears both', () => {
  const f = fixture(); try {
    f.set('alpha', 'backup.service\n'); f.sweep(); f.sweep();
    f.set('alpha-error', ''); f.sweep(); f.sweep();
    assert.equal(existsSync(join(f.state, '.unit-failed:alpha:backup.service.msgid')), true);
    assert.match(f.messages(), /host-units:alpha/);
    rmSync(join(f.root, 'alpha-error')); f.set('alpha', ''); f.sweep();
    assert.equal(existsSync(join(f.state, '.unit-failed:alpha:backup.service.msgid')), false);
    assert.equal(existsSync(join(f.state, '.host-units:alpha.msgid')), false);
  } finally { f.cleanup(); }
});

test('invalid snapshot cannot clear previous alerts', () => {
  const f = fixture(); try {
    f.set('alpha', 'backup.service\n'); f.sweep(); f.sweep();
    f.set('alpha', '../bad.service\n'); f.sweep(); f.sweep();
    assert.equal(existsSync(join(f.state, '.unit-failed:alpha:backup.service.msgid')), true);
    assert.match(f.messages(), /invalid failed-unit snapshot/);
  } finally { f.cleanup(); }
});

test('orphaned alert IDs recover from a healthy snapshot without a prior unit list', () => {
  const f = fixture(); try {
    writeFileSync(join(f.state, '.unit-failed:old.service.msgid'), 'old-local');
    writeFileSync(join(f.state, '.unit-failed:alpha:old.service.msgid'), 'old-alpha');
    f.set('alpha-error', '');
    f.sweep();
    assert.equal(existsSync(join(f.state, '.unit-failed:old.service.msgid')), false);
    assert.equal(existsSync(join(f.state, '.unit-failed:alpha:old.service.msgid')), true);
    assert.match(f.messages(), /delete\|old-local/);
    assert.doesNotMatch(f.messages(), /delete\|old-alpha/);
    rmSync(join(f.root, 'alpha-error'));
    f.sweep();
    assert.equal(existsSync(join(f.state, '.unit-failed:alpha:old.service.msgid')), false);
    assert.match(f.messages(), /delete\|old-alpha/);
  } finally { f.cleanup(); }
});

test('local sweep preserves existing Pi alert keys and --local skips remote hosts', () => {
  const f = fixture(); try {
    f.set('pi', 'local.service\n'); f.set('alpha-error', '');
    f.sweep(['--local']); f.sweep(['--local']);
    assert.match(f.messages(), /DOWN pi unit-failed:local.service/);
    assert.doesNotMatch(f.messages(), /host-units:alpha/);
    f.set('pi', ''); f.sweep(['--local']);
    assert.equal(existsSync(join(f.state, '.unit-failed:local.service.msgid')), false);
  } finally { f.cleanup(); }
});

test('strict local deployment probe does not inspect remote units or alter alert state', () => {
  const f = fixture(); try {
    f.set('alpha-error', ''); f.sweep(['--strict', '--local']);
    assert.equal(f.messages(), '');
    assert.equal(existsSync(join(f.state, '.failed-units')), false);
  } finally { f.cleanup(); }
});

test('failed job survives cleared systemd state and clears only after successful rerun', () => {
  const f = fixture(); try {
    let r = f.run(join(source, 'record.sh'), ['backup.service'], { SERVICE_RESULT: 'exit-code' });
    assert.equal(r.status, 0, r.stderr);
    r = f.run(join(source, 'snapshot.sh')); assert.equal(r.status, 0, r.stderr); assert.equal(r.stdout, 'backup.service\n');
    f.set('live', 'other.service loaded failed failed description\n');
    r = f.run(join(source, 'snapshot.sh')); assert.equal(r.stdout, 'backup.service\nother.service\n');
    f.set('live', '');
    r = f.run(join(source, 'record.sh'), ['backup.service'], { SERVICE_RESULT: 'success' }); assert.equal(r.status, 0, r.stderr);
    r = f.run(join(source, 'snapshot.sh')); assert.equal(r.status, 0, r.stderr); assert.equal(r.stdout, '');
  } finally { f.cleanup(); }
});

test('snapshot command failure is distinguishable from an empty healthy snapshot', () => {
  const f = fixture(); try {
    f.set('list-error', ''); const r = f.run(join(source, 'snapshot.sh')); assert.notEqual(r.status, 0);
  } finally { f.cleanup(); }
});

test('failed Discord deletion remains retryable after the unit has recovered', () => {
  const f = fixture(); try {
    f.set('alpha', 'backup.service\n'); f.sweep(); f.sweep();
    f.set('delete-error', ''); f.set('alpha', ''); f.sweep(); f.sweep();
    assert.equal(existsSync(join(f.state, '.unit-failed:alpha:backup.service.msgid')), true);
    assert.equal(f.messages().split('\n').filter(s => s.startsWith('delete|')).length, 2);
    rmSync(join(f.root, 'delete-error')); f.sweep();
    assert.equal(existsSync(join(f.state, '.unit-failed:alpha:backup.service.msgid')), false);
  } finally { f.cleanup(); }
});

test('failed notification delivery retries without aborting other host checks', () => {
  const f = fixture(); try {
    f.set('post-error', ''); f.set('alpha', 'backup.service\n'); f.set('epsilon', 'other.service\n');
    f.sweep(); f.sweep();
    assert.equal(existsSync(join(f.state, '.unit-failed:alpha:backup.service.msgid')), false);
    assert.equal(readFileSync(join(f.state, 'unit-failed:epsilon:other.service'), 'utf8'), '2\n');
    rmSync(join(f.root, 'post-error')); f.sweep();
    assert.equal(existsSync(join(f.state, '.unit-failed:alpha:backup.service.msgid')), true);
    assert.equal(existsSync(join(f.state, '.unit-failed:epsilon:other.service.msgid')), true);
  } finally { f.cleanup(); }
});

test('unreadable Pi snapshot preserves local alerts and still inspects remote hosts', () => {
  const f = fixture(); try {
    f.set('pi', 'local.service\n'); f.sweep(); f.sweep();
    f.set('pi-error', ''); f.set('alpha', 'backup.service\n'); f.sweep(); f.sweep();
    assert.equal(existsSync(join(f.state, '.unit-failed:local.service.msgid')), true);
    assert.match(f.messages(), /host-units:pi/);
    assert.match(f.messages(), /unit-failed:alpha:backup.service/);
  } finally { f.cleanup(); }
});
