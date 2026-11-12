import { appendFileSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const documentation = 'formatting agent-docs';
const lightweight = 'formatting sops-files change-detection agent-docs worktree-bootstrap-guard check-flake-file deploy-schema ci-workflow tofu home-state-backup';
const configuration = 'cachix-push ci-package-targets service-definitions host-persistence pi-image-configuration backup-exports monitoring-fleet btrfs-health fleet-failed-units pi-services-export coredump-collector hermes-crash-triage free-model-watch hermes-package-triage browse-mcp';

const full = reason => ({
  runHosts: true,
  runPersistenceVm: true,
  // Isolate the two expensive Nix checks without one runner per small check.
  checkMatrix: { include: [
    { group: 'lightweight', checks: lightweight },
    { group: 'configuration', checks: configuration },
    { group: 'shellcheck', checks: 'generated-shellcheck' },
    { group: 'fleet-cli', checks: 'fleet-cli' },
  ] },
  reason,
});

const documentationOnly = path =>
  path.startsWith('docs/') ||
  (path.startsWith('.agents/') && path.endsWith('.md')) ||
  ['AGENTS.md', 'README.md', 'CONTRIBUTING.md', '.github/upstream/README.md'].includes(path);

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
  // GitHub's compare API exposes at most 300 changed files. Unknown or
  // truncated comparisons must still prebuild rather than risk cache misses.
  const knownPaths = Array.isArray(paths) && paths.length > 0 && paths.length < 300 &&
    paths.every(p => typeof p === 'string' && p);
  // Main pushes always run the full safety net.
  if (eventName === 'push') return full('full validation for push');
  // Exact-SHA dispatch and unexpected events cannot skip validation.
  if (eventName !== 'pull_request') return full(`full validation for ${eventName}`);
  if (!knownPaths) return full('unknown or truncated comparison');
  if (paths.every(documentationOnly)) {
    return {
      runHosts: false,
      runPersistenceVm: false,
      checkMatrix: { include: [{ group: 'documentation', checks: documentation }] },
      reason: 'documentation-only change',
    };
  }
  return {
    runHosts: true,
    runPersistenceVm: paths.some(affectsPersistence),
    checkMatrix: full().checkMatrix,
    reason: 'selected by changed paths',
  };
}

// Dependency injection lets tests exercise real event JSON and comparison
// handling without requiring authenticated GitHub access.
export function detect({
  eventName = process.env.GITHUB_EVENT_NAME,
  eventPath = process.env.GITHUB_EVENT_PATH,
  repo = process.env.GITHUB_REPOSITORY,
  compare = (repository, base, head) => spawnSync('gh', [
    'api', '--method', 'GET', `repos/${repository}/compare/${base}...${head}`,
  ], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 }),
} = {}) {
  if (eventName !== 'pull_request' && eventName !== 'push')
    return classifyChanges(null, eventName);
  try {
    const event = JSON.parse(readFileSync(eventPath, 'utf8'));
    const base = eventName === 'push' ? event.before : event.pull_request?.base?.sha;
    const head = eventName === 'push' ? event.after : event.pull_request?.head?.sha;
    if (!/^[a-f0-9]{40}$/i.test(base ?? '') || !/^[a-f0-9]{40}$/i.test(head ?? '') ||
        !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo ?? '')) return classifyChanges(null, eventName);
    const result = compare(repo, base, head);
    if (result.status !== 0 || result.error) {
      console.warn('Change lookup failed; running full validation:', result.stderr || result.error);
      return classifyChanges(null, eventName);
    }
    const comparison = JSON.parse(result.stdout);
    if (!Array.isArray(comparison.files) || comparison.files.length >= 300)
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
    `run_hosts=${impact.runHosts}`,
    `run_persistence_vm=${impact.runPersistenceVm}`,
    `check_matrix=${JSON.stringify(impact.checkMatrix)}`,
  ].join('\n') + '\n';
  appendFileSync(process.env.GITHUB_OUTPUT, outputs);
  appendFileSync(process.env.GITHUB_STEP_SUMMARY,
    `CI impact: ${impact.reason}; host evaluations: ${impact.runHosts}; persistence VM: ${impact.runPersistenceVm}.\n`);
  console.log(outputs.trim());
}
