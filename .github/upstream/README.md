# Upstream watchers

The watcher registry at [watchers.json](watchers.json) is the source of truth for
active watcher IDs, inputs, lifecycle modes, and apply coupling. The detectors
and validators in [../scripts](../scripts) implement the package-specific
checks. Do not copy their details into this document.

## Ownership

- [upstream-watch.yml](../workflows/upstream-watch.yml) checks the `main` pins
  every two hours, after successful lock updates, and on manual dispatch.
  [upstream-readiness.py](../scripts/upstream-readiness.py) only detects status.
- `post-lock` watchers retire one self-contained workaround file,
  `modules/aspects/upstream/<watcher>.nix`, either through an independent
  cleanup PR or an apply-coupled lock candidate. Permanent aspects and host
  includes stay unchanged.
- `notify-only` watchers report readiness in the workflow summary and post
  a deduplicated Discord notification when the status changes. Delivery state
  lives on `automation/upstream-notify-state`. A notification is not proof of
  a working deployment.
- [lock-update.yml](../workflows/lock-update.yml) owns input changes.
  [upstream-plan.py](../scripts/upstream-plan.py) checks `coupling: apply`
  watchers **before** publishing a candidate lock. An upstream fix or
  incompatible package change must be handled in the same candidate as the
  workaround removal, or the update is blocked.
- Pi owns runtime readiness and completion for host-specific watchers through
  `fleet-readiness-probe` and `fleet-readiness-deliver`. GitHub pin
  readiness does not replace host checks.

## Safety rules

Readiness requires evidence from the exact selected source or commit ancestry;
version strings and release notes alone are not enough. A notify-only discovery
candidate, such as an FSR4/RDNA2 release, still needs real hardware and runtime
verification before it can be treated as supported.

Cleanup publication must preserve the expected candidate tree and branch
ownership. Never overwrite modified reviewer branches or proceed on missing
evidence. GitHub Actions validates the exact SHA and merges only after required
checks pass on a branch current with `main`. Apply-coupled cleanups also
require candidate-lock provenance and their package compatibility checks.

For a new or edited workaround, test the workaround's behavior before opening
the PR, then verify what single-file removal does. Against a pin with the fix,
test the replacement package when evaluation is insufficient. Record what was
tested and what still needs runtime evidence. See
[watch-upstream](../../.agents/skills/watch-upstream/SKILL.md) for the authoring
and retirement procedure.

## Checks

Run the focused fixture tests after changing detectors, publication, or the
atomic planner:

```sh
python3 .github/scripts/upstream-readiness.test.py
python3 .github/scripts/upstream-publish.test.py
python3 .github/scripts/upstream-plan.test.py
```

These tests verify the automation's logic. They do not establish package
builds, deployment readiness, or live notification delivery. Cleanup-candidate
CI uses [upstream-validate.py](../scripts/upstream-validate.py) for targeted
package builds and generated behavior checks.
