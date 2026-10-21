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
    is-active) [ ! -f "$MOCK_ROOT/unit-inactive" ];;
    is-failed) echo inactive; exit 0;;
    list-units) [ ! -f "$MOCK_ROOT/list-error" ]; cat "$MOCK_ROOT/live";;
    *) exit 2;; esac`);
  mock('curl', `printf '%s' "$(cat "$MOCK_ROOT/http-status" 2>/dev/null || echo 200)"`);
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
  function sweep(args = []) { return run(probeBody, args); }
  function messages() { return existsSync(join(root, 'messages')) ? readFileSync(join(root, 'messages'), 'utf8') : ''; }
  return { root, state, evidence, run, sweep, messages, set: (name, text) => writeFileSync(join(root, name), text), cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

test('read-only probe reports local and remote retained failures without notifying', () => {
  const f = fixture(); try {
    f.set('pi', 'local.service\n'); f.set('alpha', 'backup.service\n');
    const r = f.sweep(); assert.notEqual(r.status, 0);
    assert.match(r.stderr, /local.service/); assert.match(r.stderr, /backup.service/);
    assert.equal(f.messages(), ''); assert.equal(existsSync(join(f.state, '.failed-units')), false);
  } finally { f.cleanup(); }
});

test('snapshot failure is visible and local mode avoids remote snapshots', () => {
  const f = fixture(); try {
    f.set('alpha-error', '');
    assert.notEqual(f.sweep().status, 0);
    assert.equal(f.sweep(['--local']).status, 0);
    f.set('pi-error', ''); assert.notEqual(f.sweep(['--local']).status, 0);
    assert.equal(f.messages(), '');
  } finally { f.cleanup(); }
});

test('strict deployment readiness remains independent of alert state and remote units', () => {
  const f = fixture(); try {
    f.set('alpha-error', ''); f.set('pi', 'unrelated-job.service\n');
    assert.equal(f.sweep(['--strict', '--local']).status, 0);
    f.set('unit-inactive', ''); assert.notEqual(f.sweep(['--strict', '--local']).status, 0);
    assert.equal(f.messages(), '');
  } finally { f.cleanup(); }
});

test('required HTTP health response still gates strict readiness', () => {
  const f = fixture(); try {
    f.set('http-status', '503');
    assert.notEqual(f.sweep(['--strict']).status, 0);
    assert.equal(f.messages(), '');
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
    const success = Number(readFileSync(join(f.evidence, '.success', 'backup.service'), 'utf8'));
    assert.ok(success > 0 && success <= Math.floor(Date.now() / 1000));
    r = f.run(join(source, 'record.sh'), ['backup.service'], { SERVICE_RESULT: 'exit-code' }); assert.equal(r.status, 0, r.stderr);
    assert.equal(Number(readFileSync(join(f.evidence, '.success', 'backup.service'), 'utf8')), success);
    r = f.run(join(source, 'record.sh'), ['backup.service'], { SERVICE_RESULT: 'success' }); assert.equal(r.status, 0, r.stderr);
    r = f.run(join(source, 'snapshot.sh')); assert.equal(r.status, 0, r.stderr); assert.equal(r.stdout, '');
  } finally { f.cleanup(); }
});

test('snapshot command failure is distinguishable from an empty healthy snapshot', () => {
  const f = fixture(); try {
    f.set('list-error', ''); const r = f.run(join(source, 'snapshot.sh')); assert.notEqual(r.status, 0);
  } finally { f.cleanup(); }
});
