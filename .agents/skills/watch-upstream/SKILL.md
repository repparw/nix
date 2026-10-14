---
name: watch-upstream
description: Track an upstream fix in this flake's inputs, prepare validated cleanup, and retire the workaround after its completion gates pass.
---

# Watch upstream

Use the repository's `.github/workflows/upstream-watch.yml`. GitHub Actions
owns detection and repository cleanup candidates. `lock-update.yml` owns lock
publication, and Pi owns fleet deployment. Host-owned completion stays local
when it needs running-service state or safe runtime-override removal.

Before adding a watcher, identify the workaround paths, selected input,
precise source or ancestry predicate, cleanup edits, package build gates, and
completion owner in its GitHub issue. Follow
[the migration contract](../../../.github/upstream/README.md).

Add detection to `.github/scripts/upstream-readiness.py`. Detectors inspect
only the checked-out `main` pins and never update the lock or publish. Distinguish
upstream waiting, merged but unpinned, pinned ready, unavailable, and completed.
An unavailable API or build must fail closed. A version or release date alone
never proves a fix. For ancestry, require `merge_base_commit.sha` to equal the
fix commit, accepting `ahead` and `identical`. If commit ancestry cannot prove
the fix, verify the exact selected source or behavior instead.

Prepare narrow, deterministic cleanup recipes under `.github/upstream/cleanup/`.
Require `git apply --check` against the exact candidate base. Preserve unrelated
configuration. A conflict needs review; never force an old patch onto changed
code. Evaluate every affected host, inspect generated units where applicable,
and build the real package rather than relying on stubbed configuration checks.
Dispatch CI on the candidate SHA because bot-token pushes do not start it.
Reuse an existing cleanup PR without overwriting reviewer changes or repeating
successful CI. Judge completion on current `main`, never a mutable checkout.

The live Authelia pilot owns CI publication until its full lifecycle passes:
expected cleanup PR, green exact-SHA CI including the native ARM package,
subsequent PR reuse without writes or redispatch, merge, and observed completion
on `main`. Fixture tests and a successful waiting run are supporting evidence,
not this cutover gate. Keep other prepared recipes dry-run-only and local timers
in charge until then. Transfer each publication owner once, then disable its
local timer and close replaced draft PRs. Register every worked PR in T3 Code.

Run both watcher test scripts named in the migration contract. For runtime
inspection or deployment, use fleet-operations. Retire a host-owned watcher only
when the issue's runtime completion condition is proven. In particular, do not
remove Moonshine's test override while a stream is active or before its tested
fix is present in the deployed package.
