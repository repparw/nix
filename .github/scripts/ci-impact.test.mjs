import assert from 'node:assert/strict';
import test from 'node:test';
import { changedPaths, classifyChanges } from './ci-impact.mjs';

function verify(paths, { hosts, vm, groups }) {
  const result = classifyChanges(paths);
  assert.equal(result.runHosts, hosts);
  assert.equal(result.runPersistenceVm, vm);
  assert.deepEqual(result.checkMatrix.include.map(g => g.group), groups);
}

const both = ['lightweight', 'configuration'];
test('documentation-only PRs still run lightweight validation', () => {
  verify(['docs/runbooks/host-persistence.md', 'README.md'], { hosts: false, vm: false, groups: ['lightweight'] });
});

test('unrelated service, AI and GUI changes do not run the persistence VM', () => {
  for (const path of ['modules/aspects/ai/codex.nix', 'modules/aspects/gui/browser.nix',
    'modules/aspects/services/hermes.nix', 'modules/_tests/free-model-watch.py']) {
    verify([path], { hosts: true, vm: false, groups: both });
  }
});

test('persistence, recovery, boot and CI infrastructure changes run the VM', () => {
  for (const path of ['modules/aspects/persistence.nix', 'modules/_tests/host-persistence-vm.nix',
    'modules/_tests/host-persistence.nix', 'modules/scripts/host-recovery.sh',
    'modules/aspects/backup.nix', 'modules/hosts/pi.nix', 'modules/hosts/epsilon.nix',
    'modules/entities.nix', 'flake.lock', 'flake.nix', 'modules/checks.nix',
    '.github/workflows/ci.yml', '.github/workflows/revision-validation.yml',
    '.github/scripts/ci-impact.mjs']) {
    verify([path], { hosts: true, vm: true, groups: both });
  }
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
    assert.equal(classifyChanges(files).runNeovim, true);
  }
  for (const event of ['push', 'workflow_dispatch', 'unknown']) {
    const result = classifyChanges(['README.md'], event);
    assert.equal(result.runHosts, true);
    assert.equal(result.runNeovim, true);
    assert.equal(result.runPersistenceVm, true);
    assert.deepEqual(result.checkMatrix.include.map(g => g.group), both);
  }
});

test('host Neovim builds for locks, follows declarations, modules and CI changes', () => {
  for (const path of ['flake.lock', 'flake.nix', 'modules/aspects/nixvim.nix',
    'modules/aspects/cli/editors.nix', 'modules/aspects/style.nix',
    'modules/neovim-build.nix', '.github/workflows/revision-validation.yml',
    '.github/scripts/ci-impact.mjs']) {
    assert.equal(classifyChanges([path]).runNeovim, true, path);
  }
  assert.equal(classifyChanges(['docs/notes.md']).runNeovim, false);
});
