import { appendFileSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const documentation = 'formatting agent-docs';
const lightweight = 'formatting sops-files change-detection agent-docs check-flake-file deploy-schema ci-workflow tofu home-state-backup';
const configuration = 'generated-shellcheck fleet-cli service-definitions host-persistence pi-image-configuration backup-exports monitoring-fleet btrfs-health fleet-failed-units pi-services-export coredump-collector hermes-crash-triage free-model-watch hermes-package-triage';

const full = reason => ({
  runNeovim: true,
  runHosts: true,
  runPersistenceVm: true,
  checkMatrix: { include: [{ group: 'lightweight', checks: lightweight }, { group: 'configuration', checks: configuration }] },
  reason,
});

const documentationOnly = path =>
  path.startsWith('docs/') ||
  (path.startsWith('.agents/') && path.endsWith('.md')) ||
  ['AGENTS.md', 'README.md', 'CONTRIBUTING.md', '.github/upstream/README.md'].includes(path);

// Match the inputs actually used by the persistence/recovery VM, plus host
// boot/storage changes and tooling that could affect how it is evaluated.
// Neovim is a separate cached CI build: select only inputs capable of
// changing Alpha's Nixvim/Stylix-extended package or its publishing contract.
export const affectsNeovim = path => [
  'flake.nix',
  'flake.lock',
  'modules/dendritic.nix',
  'modules/entities.nix',
  'modules/defaults.nix',
  'modules/hosts/alpha.nix',
  'modules/aspects/nixvim.nix',
  'modules/aspects/nixpkgs.nix',
  'modules/aspects/nix.nix',
  'modules/aspects/style.nix',
  'modules/aspects/cli/editors.nix',
  'modules/neovim-build.nix',
  '.github/scripts/ci-impact.mjs',
  '.github/scripts/publish-neovim.sh',
  '.github/workflows/revision-validation.yml',
].includes(path);

const affectsPersistence = path =>
  ['flake.nix', 'flake.lock', 'modules/checks.nix', 'modules/entities.nix',
    'modules/pi-image.nix', 'modules/aspects/persistence.nix', 'modules/aspects/backup.nix', 'modules/aspects/host-backup.nix',
    'modules/scripts/prepare-backup-exports.py', 'modules/aspects/pi-services-backup.nix',
    'modules/_tests/backup-exports.py',
    'modules/aspects/nix.nix', 'modules/aspects/nixpkgs.nix',
    'modules/hosts/pi.nix', 'modules/hosts/epsilon.nix',
    '.github/workflows/ci.yml', '.github/workflows/revision-validation.yml'].includes(path) ||
  path.startsWith('modules/_tests/host-persistence') ||
  path.startsWith('.github/scripts/ci-impact');

// A rename can remove a persistence input even when the new name is unrelated.
export const changedPaths = files =>
  files.flatMap(file => [file.filename, file.previous_filename].filter(Boolean));

export function classifyChanges(paths, eventName = 'pull_request') {
  // GitHub's compare API exposes at most 300 changed files. Unknown or
  // truncated comparisons must still prebuild rather than risk cache misses.
  const knownPaths = Array.isArray(paths) && paths.length > 0 && paths.length < 300 &&
    paths.every(p => typeof p === 'string' && p);
  // Main pushes still run the full safety net. Only the separately published
  // Neovim build may skip when the push's exact diff is unrelated.
  if (eventName !== 'pull_request') {
    return {
      ...full(`full validation for ${eventName}`),
      runNeovim: !knownPaths || paths.some(affectsNeovim),
    };
  }
  if (!knownPaths) return full('unknown or truncated comparison');
  if (paths.every(documentationOnly)) {
    return {
      runNeovim: false,
      runHosts: false,
      runPersistenceVm: false,
      checkMatrix: { include: [{ group: 'documentation', checks: documentation }] },
      reason: 'documentation-only change',
    };
  }
  return {
    runNeovim: paths.some(affectsNeovim),
    runHosts: true,
    runPersistenceVm: paths.some(affectsPersistence),
    checkMatrix: full().checkMatrix,
    reason: 'selected by changed paths',
  };
}

function detect() {
  const eventName = process.env.GITHUB_EVENT_NAME;
  if (eventName !== 'pull_request' && eventName !== 'push')
    return classifyChanges(null, eventName);
  try {
    const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
    const base = eventName === 'push' ? event.before : event.pull_request?.base?.sha;
    const head = eventName === 'push' ? event.after : event.pull_request?.head?.sha;
    const repo = process.env.GITHUB_REPOSITORY;
    if (!/^[a-f0-9]{40}$/i.test(base ?? '') || !/^[a-f0-9]{40}$/i.test(head ?? '') ||
        !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo ?? '')) return classifyChanges(null, eventName);
    const result = spawnSync('gh', ['api', '--method', 'GET', `repos/${repo}/compare/${base}...${head}`], {
      encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
    });
    if (result.status !== 0 || result.error) {
      console.warn('Change lookup failed; running full validation:', result.stderr || result.error);
      return classifyChanges(null, eventName);
    }
    const comparison = JSON.parse(result.stdout);
    // total_files is not guaranteed, so length >= 300 also triggers full validation.
    if (!Array.isArray(comparison.files) || comparison.files.length >= 300 ||
        (typeof comparison.total_files === 'number' && comparison.total_files > comparison.files.length))
      return classifyChanges(null, eventName);
    return classifyChanges(changedPaths(comparison.files), eventName);
  } catch (error) {
    console.warn('Change detection failed; running full validation:', error);
    return classifyChanges(null, eventName);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const impact = detect();
  const outputs = [
    `run_neovim=${impact.runNeovim}`,
    `run_hosts=${impact.runHosts}`,
    `run_persistence_vm=${impact.runPersistenceVm}`,
    `check_matrix=${JSON.stringify(impact.checkMatrix)}`,
  ].join('\n') + '\n';
  appendFileSync(process.env.GITHUB_OUTPUT, outputs);
  appendFileSync(process.env.GITHUB_STEP_SUMMARY,
    `CI impact: ${impact.reason}; host evaluations: ${impact.runHosts}; Neovim prebuild: ${impact.runNeovim}; persistence VM: ${impact.runPersistenceVm}.\n`);
  console.log(outputs.trim());
}
