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
test('documentation-only PRs select only formatting and documentation checks', () => {
  for (const paths of [['docs/runbooks/host-persistence.md', 'README.md'],
    ['docs/research/audio.md'], ['.github/upstream/README.md'],
    ['AGENTS.md'], ['.agents/skills/verify-nixos-config/SKILL.md']]) {
    const result = classifyChanges(paths);
    assert.equal(result.runHosts, false);
    assert.equal(result.runNeovim, false);
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
    assert.equal(result.runNeovim, false);
    assert.equal(result.runPersistenceVm, true);
    assert.deepEqual(result.checkMatrix.include.map(g => g.group), both);
  }
});

test('Neovim prebuild follows package, inputs, Stylix and publishing changes', () => {
  for (const path of [
    'flake.lock', 'flake.nix', 'modules/dendritic.nix', 'modules/entities.nix',
    'modules/defaults.nix', 'modules/hosts/alpha.nix', 'modules/aspects/nixvim.nix',
    'modules/aspects/cli/editors.nix', 'modules/aspects/style.nix',
    'modules/aspects/nixpkgs.nix', 'modules/aspects/nix.nix',
    'modules/neovim-build.nix', '.github/workflows/revision-validation.yml',
    '.github/scripts/ci-impact.mjs', '.github/scripts/publish-neovim.sh',
  ]) {
    assert.equal(classifyChanges([path]).runNeovim, true, path);
    assert.equal(classifyChanges([path], 'push').runNeovim, true, path);
  }
});

test('unrelated changes do not rebuild Neovim on PRs or main pushes', () => {
  for (const path of [
    'modules/git-hooks.nix', 'modules/aspects/services/hermes.nix',
    'modules/aspects/gui/niri.nix', 'modules/checks.nix',
    '.github/scripts/ci-impact.test.mjs', '.github/workflows/ci.yml',
    'docs/notes.md',
  ]) {
    assert.equal(classifyChanges([path]).runNeovim, false, path);
    assert.equal(classifyChanges([path], 'push').runNeovim, false, path);
  }
  assert.equal(classifyChanges([
    'modules/git-hooks.nix', 'modules/aspects/cli/editors.nix',
  ]).runNeovim, true);
});

test('renames and missing diffs fail closed for Neovim publication', () => {
  const paths = changedPaths([{
    filename: 'modules/moved-editor.nix',
    previous_filename: 'modules/aspects/cli/editors.nix',
    status: 'renamed',
  }]);
  assert.equal(classifyChanges(paths).runNeovim, true);
  assert.equal(classifyChanges(paths, 'push').runNeovim, true);
  for (const event of ['push', 'workflow_dispatch', 'unknown']) {
    assert.equal(classifyChanges(null, event).runNeovim, true);
  }
});
