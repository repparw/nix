import { appendFileSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const documentation = 'formatting agent-docs';
const lightweight = 'formatting sops-files change-detection agent-docs check-flake-file deploy-schema ci-workflow tofu';
const configuration = 'generated-shellcheck fleet-cli service-definitions host-persistence pi-image-configuration backup-exports monitoring-fleet btrfs-health fleet-failed-units pi-services-export coredump-collector hermes-crash-triage free-model-watch hermes-package-triage hermes-chief-of-staff';

const full = reason => ({
  runNeovim: true,
  runHosts: true,
  runPersistenceVm: true,
  checkMatrix: { include: [{ group: 'lightweight', checks: lightweight }, { group: 'configuration', checks: configuration }] },
  reason,
});

const documentationOnly = path =>
  path.startsWith('docs/') ||
  ['README.md', 'CONTRIBUTING.md', '.github/upstream/README.md'].includes(path);

// Match the inputs actually used by the persistence/recovery VM, plus host
// boot/storage changes and tooling that could affect how it is evaluated.
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
  // All non-PR revisions retain the full safety net, including the lock updater's
  // exact-SHA dispatches and updates landing directly on main.
  if (eventName !== 'pull_request') return full(`full validation for ${eventName}`);
  // GitHub's compare API exposes at most 300 changed files. Treat the limit,
  // malformed responses and empty diffs as unknown rather than skipping checks.
  if (!Array.isArray(paths) || paths.length === 0 || paths.length >= 300 ||
      paths.some(p => typeof p !== 'string' || !p)) return full('unknown or truncated comparison');
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
    // Lock updates include transitive inputs and follows overrides. Any module
    // can change the package selected by the host, so keep this conservative.
    runNeovim: paths.some(path => ['flake.nix', 'flake.lock'].includes(path) ||
      path.startsWith('modules/') || path.startsWith('.github/')),
    runHosts: true,
    runPersistenceVm: paths.some(affectsPersistence),
    checkMatrix: full().checkMatrix,
    reason: 'selected by changed paths',
  };
}

function detect() {
  if (process.env.GITHUB_EVENT_NAME !== 'pull_request') return classifyChanges(null, process.env.GITHUB_EVENT_NAME);
  try {
    const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
    const base = event.pull_request?.base?.sha;
    const head = event.pull_request?.head?.sha;
    const repo = process.env.GITHUB_REPOSITORY;
    if (!/^[a-f0-9]{40}$/i.test(base ?? '') || !/^[a-f0-9]{40}$/i.test(head ?? '') ||
        !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo ?? '')) return full('invalid event metadata');
    const result = spawnSync('gh', ['api', '--method', 'GET', `repos/${repo}/compare/${base}...${head}`], {
      encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
    });
    if (result.status !== 0 || result.error) {
      console.warn('Change lookup failed; running full validation:', result.stderr || result.error);
      return full('comparison API unavailable');
    }
    const comparison = JSON.parse(result.stdout);
    // total_files is not guaranteed, so length >= 300 also triggers full validation.
    if (!Array.isArray(comparison.files) || comparison.files.length >= 300 ||
        (typeof comparison.total_files === 'number' && comparison.total_files > comparison.files.length))
      return full('comparison truncated');
    return classifyChanges(changedPaths(comparison.files));
  } catch (error) {
    console.warn('Change detection failed; running full validation:', error);
    return full('comparison parsing failed');
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
    `CI impact: ${impact.reason}; host evaluations: ${impact.runHosts}; persistence VM: ${impact.runPersistenceVm}.\n`);
  console.log(outputs.trim());
}
