---
name: watch-upstream
description: Track an upstream fix in this flake's inputs, prepare a validated cleanup, and retire the workaround after its completion checks pass.
---

# Watch upstream

## Who does what

GitHub Actions detects upstream fixes and publishes cleanups. Pi deploys the
fleet and runs runtime readiness probes for host-owned watchers.

- `.github/upstream/watchers.json` holds each watcher's contract.
- `upstream-watch.yml` runs detection.
- `lock-update.yml` publishes lock updates and runs the atomic planner.

Before you add, change, or retire a watcher, read the entry in
`.github/upstream/watchers.json` and the relevant detector, planner, publisher,
and validation code. These are the sources of truth for the watcher.

## Where workaround code goes

Keep each temporary workaround module self-contained under
`modules/aspects/upstream/`. Contribute to an existing, included Den aspect
through `provides`. Do not add the workaround's name to the `includes` list of a
default, role, or permanent aspect. Keep permanent behavior outside `upstream/`,
so that retiring a workaround never requires editing permanent configuration.
The flake discovers new module files on its own.

## Verify before you open a PR

Before you open a PR that adds a workaround or watcher, check both ends of its
lifecycle in a disposable worktree.

- With the workaround present, evaluate the affected NixOS or Home Manager
  options and test that the workaround fixes the problem. If evaluation is not
  enough, build or run the affected package.
- Remove only `modules/aspects/upstream/<watcher>.nix` and inspect the resulting
  configuration on the affected hosts. Check the resolved options or generated
  entries instead of building a whole system to compare configuration. Against a
  pin that contains the upstream fix, build or run the replacement package and
  confirm that the intended behavior survives the removal. Derivation hashes and
  intentionally changed options do not have to stay equal.
- If the upstream fix is not available yet, verify the single-file removal
  mechanically. Record what you can only check once a pin with the fix exists.

Do these checks case by case while you prepare the PR. They do not require a
custom CI job or a permanent test for each watcher. In the PR description, state
what you verified and what remains untested.

## Register the watcher

Add the watcher's input and lifecycle mode to `watchers.json`, and add its
readiness detector. Keep the reason for the workaround in its source file.
Do not maintain a second watcher catalog in Markdown. For `coupling: apply`,
the lock planner must include the cleanup with the candidate input update or
block publication.

Do not open a tracker issue for each watcher. Ready notices go to the run
summary. When the status changes, they also go once to the fleet Discord
channel, through the approved bot identity.

## Write the readiness detector

Add detection to `.github/scripts/upstream-readiness.py`. A detector reads the
pins on the checked-out `main` and never publishes. It fails closed when
evidence is unavailable, so a missing source never reads as ready.

A detector reports one of four states: waiting, merged-not-pinned, pinned-ready,
or completed. A version or release date alone never proves a fix. Require commit
ancestry, meaning `merge_base_commit.sha` equals the fix commit, or check the
exact source or behavior that the pin selects.

## Clean up and retire

Each removable watcher owns one file, `modules/aspects/upstream/<watcher>.nix`.
The generic cleanup operation stages one `git rm` and checks the exact candidate
tree. Do not add per-watcher deletion tests or stored patch files. Keep the
upstream-readiness checks and the existing cleanup-candidate validation. Do not
edit permanent defaults, roles, or owner aspects.

If the file or the candidate changed since publication, require review and do
not overwrite it. Reuse an existing cleanup PR without overwriting reviewer
changes.

In `upstream-validate.py`, cleanup-candidate CI evaluates the affected host
configuration and passes only if real package builds succeed, not configuration
stubs.

Dispatch CI on the exact SHA, because pushes made with the bot token do not
start workflows. Judge completion on the current `main`, never on a mutable
checkout. Merge only when the required checks pass on the exact SHA and the branch is
current with `main`. Never overwrite modified reviewer branches or proceed on
missing evidence. A notify-only readiness notice is not a runtime proof.

Retire a host-owned watcher only after its runtime completion condition is
proven. When changing detection, publication, or planning, run the affected fixtures:
`upstream-readiness.test.py`, `upstream-publish.test.py`, and
`upstream-plan.test.py` under `.github/scripts/`. For runtime
inspection or deployment, use
[fleet-operations](../fleet-operations/SKILL.md).

Register every PR you work on in T3 Code.
