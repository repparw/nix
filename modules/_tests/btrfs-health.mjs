import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, existsSync, chmodSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const script = process.argv[2];
if (!script) throw new Error('Pass the evaluated btrfs-health-root service script');
const fixture = (free = '21474836480', metadata = '78.10', reserve = '0', estimated = '214748364800') =>
  `Overall:\n    Device unallocated: ${free}\n    Free (estimated): ${estimated}\n    Global reserve: 536870912 (used: ${reserve})\nMetadata,DUP: Size:12348030976, Used:9643311104 (${metadata}%)\n`;

function harness() {
  const dir = mkdtempSync(join(tmpdir(), 'btrfs-health-test-'));
  const command = join(dir, 'btrfs');
  writeFileSync(command, `#!/bin/sh
set -eu
case "$*" in
  'filesystem usage -b /')
    if [ -f "$STATE_DIRECTORY/usage" ]; then cat "$STATE_DIRECTORY/usage";
    else printf '%s\\n' "$BTRFS_USAGE"; fi;;
  'balance start -dusage=0 -musage=0 /'|'balance start -dusage=25,limit=8 /')
    printf '%s\\n' "$*" >> "$STATE_DIRECTORY/calls"
    [ "$BTRFS_BALANCE_FAIL" != 1 ] || exit 1
    case "$*" in
      *musage=0*) next="$BTRFS_EMPTY_USAGE";;
      *) next="$BTRFS_FILTERED_USAGE";;
    esac
    if [ -n "$next" ]; then printf '%s\\n' "$next" > "$STATE_DIRECTORY/usage"; fi;;
  *) exit 99;;
esac
`);
  chmodSync(command, 0o755);
  return {
    dir,
    run(usage, extra = {}) {
      return spawnSync('bash', [script], {
        encoding: 'utf8',
        env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, STATE_DIRECTORY: dir, BTRFS_USAGE: usage,
          BTRFS_EMPTY_USAGE: '', BTRFS_FILTERED_USAGE: '', BTRFS_BALANCE_FAIL: '', ...extra },
      });
    },
    count() { return readFileSync(join(dir, 'global-reserve-count'), 'utf8').trim(); },
    calls() { return existsSync(join(dir, 'calls')) ? readFileSync(join(dir, 'calls'), 'utf8') : ''; },
    close() { rmSync(dir, { recursive: true, force: true }); },
  };
}

test('zero reserve clears prior consecutive usage and accepts byte-mode free space', () => {
  const h = harness();
  try {
    writeFileSync(join(h.dir, 'global-reserve-count'), '7\n');
    assert.equal(h.run(fixture()).status, 0);
    assert.equal(h.count(), '0');
    assert.equal(h.calls(), '');
  } finally { h.close(); }
});

test('empty chunks alone can recover allocation without relocating live data', () => {
  const h = harness();
  try {
    assert.equal(h.run(fixture('1052672'), { BTRFS_EMPTY_USAGE: fixture() }).status, 0);
    assert.equal(h.calls(), 'balance start -dusage=0 -musage=0 /\n');
  } finally { h.close(); }
});

test('one limited low-usage pass recovers pressure and then stops', () => {
  const h = harness();
  try {
    assert.equal(h.run(fixture('1052672'), { BTRFS_FILTERED_USAGE: fixture() }).status, 0);
    assert.equal(h.calls(), 'balance start -dusage=0 -musage=0 /\nbalance start -dusage=25,limit=8 /\n');
  } finally { h.close(); }
});

test('insufficient space, crowded metadata or reserve use prevents live-data relocation', () => {
  for (const usage of [fixture('1052672', undefined, undefined, '8589934592'),
    fixture('1052672', '97.00'), fixture('1052672', undefined, '1048576')]) {
    const h = harness();
    try {
      assert.equal(h.run(usage).status, 1);
      assert.equal(h.calls(), 'balance start -dusage=0 -musage=0 /\n');
    } finally { h.close(); }
  }
});

test('unsuccessful reclamation stays unhealthy and does not escalate', () => {
  const h = harness();
  try {
    assert.equal(h.run(fixture('1052672')).status, 1);
    assert.equal(h.calls().trim().split('\n').length, 2);
  } finally { h.close(); }
  const failed = harness();
  try {
    assert.equal(failed.run(fixture('1052672'), { BTRFS_BALANCE_FAIL: '1' }).status, 1);
    assert.equal(failed.calls().trim().split('\n').length, 1);
  } finally { failed.close(); }
});

test('persistent reserve fails on the third consecutive check and resets after recovery', () => {
  const h = harness();
  try {
    assert.equal(h.run(fixture(undefined, undefined, '1048576')).status, 0);
    assert.equal(h.run(fixture(undefined, undefined, '1048576')).status, 0);
    const failure = h.run(fixture(undefined, undefined, '1048576'));
    assert.equal(failure.status, 1);
    assert.match(failure.stdout, /3 consecutive checks: 1048576/);
    assert.equal(h.run(fixture()).status, 0);
    assert.equal(h.count(), '0');
  } finally { h.close(); }
});

test('low unallocated and high metadata retain their actual failure thresholds', () => {
  const h = harness();
  try {
    const low = h.run(fixture('1052672'));
    assert.equal(low.status, 1);
    assert.match(low.stdout, /1052672 bytes < 10 GiB/);
    assert.doesNotMatch(low.stdout, /reserve is currently in use/);
    assert.equal(h.run(fixture(undefined, '97.00')).status, 1);
    assert.equal(h.run(fixture('10737418240', '96.99')).status, 0);
  } finally { h.close(); }
});

test('missing or malformed numeric fields fail visibly before changing reserve state', () => {
  const h = harness();
  try {
    for (const usage of ['', fixture('1.00MiB'), fixture(undefined, 'bad'), fixture(undefined, undefined, '0.00B')]) {
      const result = h.run(usage);
      assert.equal(result.status, 1);
      assert.match(result.stderr, /cannot parse/);
    }
  } finally { h.close(); }
});
