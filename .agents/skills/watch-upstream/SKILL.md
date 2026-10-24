---
name: watch-upstream
description: Track an upstream fix in this flake's inputs, prepare validated cleanup, and retire the workaround after its completion gates pass.
---

# Watch upstream

GitHub Actions owns detection and cleanup publication. Watcher contracts live
in `.github/upstream/watchers.json`; `upstream-watch.yml` runs detection,
`lock-update.yml` owns lock publication and the atomic planner, and Pi owns
fleet deployment plus runtime readiness probes for host-owned watchers.
[The migration contract](../../../.github/upstream/README.md) is the source of
truth for publication policy and per-watcher gates.

Record each watcher's workaround paths, selected input, precise source or
ancestry predicate, cleanup edits, build gates, and completion owner in
`watchers.json` and the linked repository documentation or cleanup recipe.
Watchers do not require GitHub issues. Readiness without an optional legacy
issue is reported in the workflow summary; do not create an issue or a separate
agent timer just to track a watcher.

Add detection to `.github/scripts/upstream-readiness.py`. Detectors read the
checked-out `main` pins, never publish, and fail closed when evidence is
unavailable. Distinguish waiting, merged-not-pinned, pinned-ready, and
completed. A version or release date alone never proves a fix: require commit
ancestry (`merge_base_commit.sha` equals the fix commit) or verify the exact
selected source or behavior.

Cleanup recipes live in `.github/upstream/cleanup/`. Keep them narrow:
`git apply --check` must pass against the exact candidate base, unrelated
configuration is preserved, and a conflict requires review rather than a
forced patch. Evaluate every affected host and its generated units, and gate
on the real package builds in `upstream-validate.py`, not configuration
stubs. Reuse an existing cleanup PR without overwriting reviewer changes.
Dispatch CI on the exact SHA; bot-token pushes do not start workflows. Judge
completion on current `main`, never a mutable checkout. Combined atomic
lock+cleanup candidates merge-automate under the #265 policy once exact-SHA
CI is green and the branch is strict up-to-date with main; eligibility
re-verifies exact SHA, ownership, watcher manifest, required validations,
and base, and approvals fail closed without `LOCK_UPDATE_APPROVAL_TOKEN`.

CI publication is the standing owner; Authelia's combined candidate is the
first atomic firing and merge-automates under the same #265 policy — the
retired human-review gate is not restored for it. Before disabling a local
timer, verify its replacement's live CI run and all completion checks —
fixtures and waiting runs are supporting evidence, not the cutover gate.
Close replaced drafts only after their replacement validates in production.
Retire a host-owned watcher only when its recorded runtime completion
condition is proven. Run the watcher test scripts named in the migration
contract; for runtime inspection or deployment, use fleet-operations.
Register every worked PR in T3 Code.
