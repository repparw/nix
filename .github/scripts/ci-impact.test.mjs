import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { changedPaths, classifyChanges, detect } from './ci-impact.mjs';

function verify(paths, { hosts, vm, groups }) {
  const result = classifyChanges(paths);
  assert.equal(result.runHosts, hosts);
  assert.equal(result.runPersistenceVm, vm);
  assert.deepEqual(result.checkMatrix.include.map(g => g.group), groups);
}

const both = ['lightweight', 'configuration', 'shellcheck', 'fleet-cli'];
test('documentation-only PRs select only formatting and documentation checks', () => {
  for (const paths of [['docs/runbooks/host-persistence.md', 'README.md'],
    ['docs/runbooks/monitoring.md'],
    ['AGENTS.md'], ['.agents/skills/verify-nixos-config/SKILL.md']]) {
    const result = classifyChanges(paths);
    assert.equal(result.runHosts, false);
    assert.equal(result.runPersistenceVm, false);
    assert.deepEqual(result.checkMatrix.include, [{ group: 'documentation', checks: 'formatting agent-docs' }]);
  }
});

test('agent skill scripts are not treated as documentation-only', () => {
  verify(['.agents/skills/verify-nixos-config/scripts/build.sh'],
    { hosts: true, vm: false, groups: both });
});

test('unrelated service, AI and GUI changes do not run the persistence VM', () => {
  for (const path of ['modules/aspects/ai/codex.nix', 'modules/aspects/gui/browser.nix',
    'modules/aspects/services/hermes.nix', 'modules/_tests/free-model-watch.py']) {
    verify([path], { hosts: true, vm: false, groups: both });
  }
});

test('persistence, recovery, boot and CI infrastructure changes run the VM', () => {
  for (const path of ['modules/pi-image.nix', 'modules/aspects/persistence.nix', 'modules/_tests/host-persistence-vm.nix',
    'modules/_tests/host-persistence.nix', 'modules/aspects/host-backup.nix',
    'modules/scripts/prepare-backup-exports.py', 'modules/aspects/pi-services-backup.nix',
    'modules/_tests/backup-exports.py',
    'modules/aspects/backup.nix', 'modules/hosts/pi.nix', 'modules/hosts/epsilon.nix',
    'modules/entities.nix', 'flake.lock', 'flake.nix', 'modules/checks.nix',
    '.github/workflows/ci.yml', '.github/workflows/revision-validation.yml',
    '.github/scripts/ci-impact.mjs']) {
    verify([path], { hosts: true, vm: true, groups: both });
  }
});

test('watcher tests run only for relevant changes', () => {
  for (const path of [
    'flake.lock', '.github/upstream/watchers.json',
    '.github/upstream/cleanup/tasks-org.patch',
    '.github/scripts/upstream-plan.py', '.github/scripts/upstream-readiness.test.py',
    'modules/aspects/upstream/tasks-org.nix', '.github/workflows/lock-update.yml',
    '.github/workflows/revision-validation.yml', '.github/scripts/ci-impact.mjs',
  ]) assert.equal(classifyChanges([path]).runUpstreamTests, true, path);
  for (const path of [
    'modules/aspects/gui/niri.nix', 'modules/aspects/services/hermes.nix',
    '.agents/skills/watch-upstream/SKILL.md', 'docs/runbooks/host-persistence.md',
  ]) assert.equal(classifyChanges([path]).runUpstreamTests, false, path);
  assert.equal(classifyChanges(null).runUpstreamTests, true);
  assert.equal(classifyChanges(['README.md'], 'push').runUpstreamTests, true);
});

test('renames trigger checks for both the old and new file paths', () => {
  verify(changedPaths([{
    filename: 'modules/aspects/renamed.nix',
    previous_filename: 'modules/aspects/persistence.nix',
    status: 'renamed',
  }]), { hosts: true, vm: true, groups: both });
  verify(changedPaths([{
    filename: 'docs/renamed.md',
    previous_filename: 'modules/aspects/ai/codex.nix',
    status: 'renamed',
  }]), { hosts: true, vm: false, groups: both });
});

test('mixed diffs use the most conservative classification', () => {
  verify(['docs/notes.md', 'modules/aspects/persistence.nix'], { hosts: true, vm: true, groups: both });
  verify(['docs/notes.md', 'modules/aspects/ai/default.nix'], { hosts: true, vm: false, groups: both });
});

test('untrusted or incomplete comparisons never skip validation', () => {
  for (const files of [null, undefined, [], [''], [null], Array(300).fill('docs/notes.md')]) {
    verify(files, { hosts: true, vm: true, groups: both });
  }
  for (const event of ['push', 'workflow_dispatch', 'unknown']) {
    const result = classifyChanges(['README.md'], event);
    assert.equal(result.runHosts, true);
    assert.equal(result.runPersistenceVm, true);
    assert.deepEqual(result.checkMatrix.include.map(g => g.group), both);
  }
});

const before = 'a'.repeat(40);
const after = 'b'.repeat(40);
const compareResponse = files => ({ status: 0, stdout: JSON.stringify({ files }) });
function detectFixture(eventName, event, response = compareResponse([])) {
  const dir = mkdtempSync(join(tmpdir(), 'impact-event-'));
  const calls = [];
  try {
    const eventPath = join(dir, 'event.json');
    writeFileSync(eventPath, JSON.stringify(event));
    const result = detect({
      eventName,
      eventPath,
      repo: 'repparw/nix',
      compare: (repository, base, head) => {
        calls.push({ repository, base, head });
        return response;
      },
    });
    return { result, calls };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('push events skip comparison and run full validation', () => {
  const event = { before, after, ref: 'refs/heads/main' };
  const observed = detectFixture('push', event, compareResponse([
    { filename: 'modules/git-hooks.nix', status: 'modified' },
  ]));
  assert.deepEqual(observed.calls, []);
  assert.equal(observed.result.runHosts, true);
  assert.equal(observed.result.runPersistenceVm, true);
  assert.deepEqual(observed.result.checkMatrix.include.map(x => x.group), both);
});

test('real pull request event JSON selects PR base/head, not push SHAs', () => {
  const event = { pull_request: { base: { sha: before }, head: { sha: after } } };
  const observed = detectFixture('pull_request', event, compareResponse([
    { filename: 'modules/aspects/services/hermes.nix', status: 'modified' },
  ]));
  assert.deepEqual(observed.calls, [{ repository: 'repparw/nix', base: before, head: after }]);
  assert.equal(observed.result.runHosts, true);
});

test('push events ignore malformed event data and comparison responses', () => {
  const event = { before, after };
  for (const response of [
    { status: 1, stderr: 'compare failed' },
    { status: 0, stdout: '{invalid-json' },
    compareResponse(Array.from({ length: 300 }, (_, n) => ({ filename: `docs/${n}.md` }))),
    compareResponse([]),
  ]) {
    const observed = detectFixture('push', event, response);
    assert.equal(observed.result.runHosts, true);
    assert.deepEqual(observed.calls, []);
  }
  const invalid = detectFixture('push', { before: '0'.repeat(40), after: 'not-a-sha' },
    compareResponse([{ filename: 'docs/one.md' }]));
  assert.deepEqual(invalid.calls, []);
  assert.equal(detect({ eventName: 'push', eventPath: '/nonexistent-fixture',
    repo: 'invalid', compare: () => { throw Error('Must not compare'); } }).runHosts, true);
  assert.equal(detect({ eventName: 'workflow_dispatch', eventPath: '/nonexistent-fixture',
    repo: 'repparw/nix', compare: () => { throw Error('Must not compare'); } }).runHosts, true);
});

test('pull request comparison failures fail closed', () => {
  const event = { pull_request: { base: { sha: before }, head: { sha: after } } };
  for (const response of [
    { status: 1, stderr: 'compare failed' },
    { status: 0, stdout: '{invalid-json' },
    compareResponse(Array.from({ length: 300 }, (_, n) => ({ filename: `docs/${n}.md` }))),
    compareResponse([]),
  ]) {
    const observed = detectFixture('pull_request', event, response);
    assert.equal(observed.result.runHosts, true);
    assert.equal(observed.result.runPersistenceVm, true);
  }
});
