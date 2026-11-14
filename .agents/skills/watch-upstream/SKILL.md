---
name: watch-upstream
description: Track an upstream fix in this flake's inputs, prepare validated cleanup, and retire the workaround after its completion gates pass.
---

# Watch upstream

GitHub Actions owns detection and cleanup publication. Watcher contracts live
in `.github/upstream/watchers.json`; `upstream-watch.yml` runs detection,
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

For a new watcher, register its input and lifecycle mode in
`watchers.json`; add its readiness detector and choose focused validation
while implementing the workaround. Identify the owning Den aspect, affected
hosts, and the options or packages it changes:
- For configuration changes, evaluate the relevant resolved NixOS or Home
  Manager options on the affected hosts, not the whole system closure. Where
  both sides evaluate on the same pin, compare values with the workaround
  present and removed. Document any intentional differences.
- For derivation overrides, compare intended behavior rather than output
  paths or derivation hashes. Build the affected package after cleanup and
  check its actual behavior, including generated service or desktop entries
  where relevant.
- If a meaningful check requires runtime access, record the manual completion
  gate instead of inventing a generic parity assertion.

Keep these checks specific to what the workaround changes. Do not add generic
aspect-diff infrastructure or per-watcher deletion tests. Keep the reason for
the workaround in its source file. Update the migration contract only when
publication policy, safety boundaries, or completion procedures change, not
for routine watcher additions or removals. Do not open a per-watcher tracker
issue: ready notices go to the run summary and, once per status change, to
the fleet Discord channel through the approved bot identity.

Add detection to `.github/scripts/upstream-readiness.py`. Detectors read the
checked-out `main` pins, never publish, and fail closed when evidence is
unavailable. Distinguish waiting, merged-not-pinned, pinned-ready, and
completed. A version or release date alone never proves a fix: require commit
ancestry (`merge_base_commit.sha` equals the fix commit) or verify the exact
selected source or behavior.

Each removable watcher owns `modules/aspects/upstream/<watcher>.nix`.
The generic cleanup operation stages one `git rm` and checks the exact
candidate tree. Do not add per-watcher deletion tests or stored patch files.
Keep focused tests for upstream detection and the selected behavior
checks after removal. Do not edit permanent defaults, roles, or owner aspects.
If the file or candidate changed since publication, require review rather
than overwriting it. Evaluate affected host configuration and gate on real
package builds in `upstream-validate.py`, not configuration stubs. Reuse an existing cleanup PR without overwriting reviewer changes.
Dispatch CI on the exact SHA; bot-token pushes do not start workflows. Judge
completion on current `main`, never a mutable checkout. Follow the migration
contract's merge policy, including exact-SHA validation, branch ownership,
strict base freshness, and fail-closed approval checks.

Retire a host-owned watcher only when its documented runtime completion
condition is proven. Run the watcher test scripts named in the migration
contract; for runtime inspection or deployment, use
[fleet-operations](../fleet-operations/SKILL.md).
Register every worked PR in T3 Code.
