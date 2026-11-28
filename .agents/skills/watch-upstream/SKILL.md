---
name: watch-upstream
description: Track an upstream fix in this flake's inputs, prepare validated cleanup, and retire the workaround after its completion gates pass.
---

# Watch upstream

GitHub Actions owns detection and cleanup publication. Watcher contracts live
in `modules/aspects/upstream/watchers.json`; `upstream-watch.yml` runs detection,
`lock-update.yml` owns lock publication and the atomic planner, and Pi owns
fleet deployment plus runtime readiness probes for host-owned watchers.
Before adding, changing, or retiring a watcher, read
[the migration contract](../../../.github/upstream/README.md) for publication
policy, per-watcher gates, and timer or publisher cutover requirements.

Keep temporary workaround modules self-contained under
`modules/aspects/upstream/`. Contribute directly to an existing, included Den
aspect through `provides`; do not add the workaround's name to a default,
role, or permanent aspect's `includes` list. Keep permanent behavior outside
`upstream/` so retiring a workaround requires no permanent configuration edit.
The flake already discovers new module files.

Before opening a PR that adds a workaround or watcher, verify both
sides of its lifecycle in a disposable worktree:

- With the workaround present, evaluate the affected NixOS or Home Manager
  options and test that the workaround actually fixes the problem. Build or
  exercise the affected package when evaluation alone is insufficient.
- Remove only `modules/aspects/upstream/<watcher>.nix` and inspect the
  resulting configuration on the affected hosts. Check relevant resolved
  options or generated entries rather than building an entire system just to
  compare configuration. Against a pin containing the upstream fix, build or
  exercise the replacement package and verify the intended behavior survives
  removal. Do not require derivation hashes or intentionally changed options
  to remain equal.
- If the upstream fix is not yet available, verify the single-file removal
  mechanically and record what can only be checked once the fixed pin exists.

These are case-by-case checks performed while preparing the PR, not a
requirement to add a custom CI job or permanent test for each watcher. State
what was verified and what remains untested in the PR description.

Register the watcher's input and lifecycle mode in `modules/aspects/upstream/watchers.json`.
For plain PR waits, declare `repo` and `pr` directly in `watchers.json` (no Python detector needed),
and optionally set `"coupling": "bundle"` for ungated PR waits so `lock-update.yml` drops the file
atomically once `PINNED-READY`. Add a Python detector in `.github/scripts/upstream-readiness.py` only
for non-PR or custom source/release checks. Keep the reason for the workaround in its source file.
Update the migration contract only when publication policy, safety boundaries,
or completion procedures change, not for routine watcher additions or
removals. Do not open a per-watcher tracker issue: ready notices go to the run
summary and, once per status change, to the fleet Discord channel through the
approved bot identity.

Add detection to `.github/scripts/upstream-readiness.py`. Detectors read the
checked-out `main` pins, never publish, and fail closed when evidence is
unavailable. Distinguish waiting, merged-not-pinned, pinned-ready, and
completed. A version or release date alone never proves a fix: require commit
ancestry (`merge_base_commit.sha` equals the fix commit) or verify the exact
selected source or behavior.

Each removable watcher owns `modules/aspects/upstream/<watcher>.nix`.
The generic cleanup operation stages one `git rm` and checks the exact
candidate tree. Do not add per-watcher deletion tests or stored patch files.
Keep upstream-readiness checks and existing cleanup-candidate validation,
but do not add per-watcher deletion tests. Do not edit permanent defaults,
roles, or owner aspects. If the file or candidate changed since publication,
require review rather than overwriting it. Cleanup-candidate CI evaluates
affected host configuration and gates on real package builds in
`upstream-validate.py`, not configuration stubs. Reuse an existing cleanup
PR without overwriting reviewer changes.
Dispatch CI on the exact SHA; bot-token pushes do not start workflows. Judge
completion on current `main`, never a mutable checkout. Follow the migration
contract's merge policy, including exact-SHA validation, branch ownership,
strict base freshness, and fail-closed approval checks.

Retire a host-owned watcher only when its documented runtime completion
condition is proven. Run the watcher test scripts named in the migration
contract; for runtime inspection or deployment, use
[fleet-operations](../fleet-operations/SKILL.md).
Register every worked PR in T3 Code.
