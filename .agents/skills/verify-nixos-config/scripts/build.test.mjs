import assert from 'node:assert/strict';
import { execFile, execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, symlinkSync, readlinkSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { promisify } from 'node:util';
import { test } from 'node:test';

const exec = promisify(execFile);
const script = resolve(import.meta.dirname, 'build.sh');
const storePath = process.execPath.split('/').slice(0, 4).join('/');
const shell = execFileSync('bash', ['-c', 'command -v bash'], { encoding: 'utf8' }).trim();

test('build output is independent of result and each invocation keeps its evidence', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'verify-build-test.'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'bin'));
  writeFileSync(join(dir, 'bin/nix'), `#!${shell}\nprintf "%s\\n" "$VERIFY_TEST_OUTPUT"\necho build-log >&2\n`, { mode: 0o755 });
  const env = { ...process.env, PATH: `${dir}/bin:${process.env.PATH}`, VERIFY_TEST_OUTPUT: storePath };
  const run = () => exec('bash', [script, 'fixture', join(dir, 'evidence')], { cwd: dir, env });
  assert.equal((await run()).stdout, `${storePath}\n`);
  assert.equal(existsSync(join(dir, 'result')), false);
  symlinkSync('/unrelated-output', join(dir, 'result'));
  const outputs = await Promise.all([run(), run()]);
  for (const output of outputs) assert.equal(output.stdout, `${storePath}\n`);
  assert.equal(readlinkSync(join(dir, 'result')), '/unrelated-output');
  const evidence = readdirSync(join(dir, 'evidence'));
  assert.equal(evidence.length, 3);
  for (const runDir of evidence) {
    assert.equal(readFileSync(join(dir, 'evidence', runDir, 'build.log'), 'utf8'), 'build-log\n');
    assert.equal(readFileSync(join(dir, 'evidence', runDir, 'output-paths'), 'utf8'), `${storePath}\n`);
  }
});

test('a failed build retains its log and status without returning a usable output', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'verify-build-failure.'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'bin'));
  writeFileSync(join(dir, 'bin/nix'), `#!${shell}\necho /nix/store/partial-output\necho deliberate-failure >&2\nexit 37\n`, { mode: 0o755 });
  await assert.rejects(exec('bash', [script, 'fixture', join(dir, 'evidence')], {
    env: { ...process.env, PATH: `${dir}/bin:${process.env.PATH}` },
  }), error => {
    assert.equal(error.code, 37);
    assert.equal(error.stdout, '');
    assert.match(error.stderr, /deliberate-failure/);
    return true;
  });
  const [runDir] = readdirSync(join(dir, 'evidence'));
  assert.equal(readFileSync(join(dir, 'evidence', runDir, 'build.log'), 'utf8'), 'deliberate-failure\n');
});
