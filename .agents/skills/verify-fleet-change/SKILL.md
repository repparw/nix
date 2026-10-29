---
name: verify-fleet-change
description: Verify proposed NixOS fleet and Home Manager changes against observable effective configuration, generated files, systemd units, and focused tests. Use after editing modules or aspects and before requesting review or deployment.
---

# Verify fleet changes

Verify the behavior the change is meant to produce, not just whether Nix evaluates.
This skill covers the proposed configuration in the checkout. It does not
activate a host or establish running-fleet health.

## Define the claim

Read the changed source and relevant aspect composition. Before choosing a
command, identify:

- **Claim:** the specific behavior expected after the change.
- **Scope:** affected hosts/users, and hosts that should stay unchanged.
- **Observation:** an effective option, generated unit/file, package output,
  or existing test whose value would distinguish success from failure.
- **Boundary:** what that observation cannot prove without a build or runtime check.

Choose the narrowest useful observation from the
[verification routes](features/README.md). For a shared aspect or default,
cover every affected host, not only the machine running the agent. Discover
hosts from the flake rather than assuming a copied list.

## Execute and compare

Run the selected probe on the actual checkout. Compare the observed value
with the claimed outcome; a successful exit status or a derivation path alone
is not evidence of the intended behavior. Check an unaffected host or
previous value when the change could cause a regression.

For changes not yet committed, verify the working tree locally: CI validates
a committed revision, not uncommitted edits. New Nix files must be Git-tracked
for flake evaluation to include them; check the working-tree status before
claiming a successful evaluation covers newly created files. Once a PR exists,
consult CI for its exact head before repeating expensive checks. Use existing
focused tests in [modules/checks.nix](../../../modules/checks.nix) or nearby
test files; do not duplicate the entire CI matrix.

If evaluation fails, inspect the error, source diff, and aspect composition
before changing inputs or the lockfile. Never update `flake.lock` as an
incidental verification step.

Prefer evaluation and targeted generated outputs. Build a selected package
or Home Manager activation output only if its actual contents must be inspected;
a full system closure is a last resort when activation is imminent and CI
cannot provide the needed proof. Honor host-wide Nix `max-jobs` and `cores`
limits; do not override them.

## Report

State the claim, checked revision or working-tree state, affected hosts, exact
commands, observed values, expectation, and pass/fail result. Identify any
skipped hosts or unverified effects. CI's stubbed host evaluation is not a
native system build. Temporary logs are optional for quick evaluations; retain
build failure output when needed, and don't delete unrelated `result` links
or store paths.

Do not deploy, activate, use `--dry-activate`, or mutate remote host state.
For authorized activation and live service verification use
[fleet-operations](../fleet-operations/SKILL.md).
