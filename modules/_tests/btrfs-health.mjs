import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, chmodSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const script = process.argv[2];
if (!script) throw new Error('Pass the evaluated btrfs-health-root service script');
const fixture = (free = '21474836480', metadata = '78.10', reserve = '0') =>
  `Overall:\n    Device unallocated: ${free}\n    Global reserve: 536870912 (used: ${reserve})\nMetadata,DUP: Size:12348030976, Used:9643311104 (${metadata}%)\n`;

function harness() {
  const dir = mkdtempSync(join(tmpdir(), 'btrfs-health-test-'));
  const command = join(dir, 'btrfs');
  writeFileSync(command, '#!/bin/sh\n[ "$*" = "filesystem usage -b /" ] || exit 99\nprintf "%s\\n" "$BTRFS_USAGE"\n');
  chmodSync(command, 0o755);
  return {
    dir,
    run(usage) {
      return spawnSync('bash', [script], {
        encoding: 'utf8',
        env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, STATE_DIRECTORY: dir, BTRFS_USAGE: usage },
      });
    },
    count() { return readFileSync(join(dir, 'global-reserve-count'), 'utf8').trim(); },
    close() { rmSync(dir, { recursive: true, force: true }); },
  };
}

test('zero reserve clears prior consecutive usage and accepts byte-mode free space', () => {
  const h = harness();
  try {
    writeFileSync(join(h.dir, 'global-reserve-count'), '7\n');
    assert.equal(h.run(fixture()).status, 0);
    assert.equal(h.count(), '0');
  } finally { h.close(); }
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
