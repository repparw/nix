---
name: verify-fleet-change
description: Verify proposed NixOS fleet and Home Manager changes by checking effective option values, generated files, systemd units, and existing tests. Use after editing modules or aspects and before requesting review or deployment.
---

# Verify fleet changes

Check that the change does what it is meant to do. A configuration that
evaluates is not enough. This skill covers the proposed configuration in the
checkout. It does not activate a host, and it does not show that the running
fleet is healthy.

## Define the claim

Read the changed source and how the affected aspects compose. Before you pick a
command, write down four things.

- **Claim.** The specific behavior you expect after the change.
- **Scope.** The hosts and users affected, and the hosts that should stay the
  same.
- **Observation.** An effective option, generated unit or file, package output,
  or existing test whose value differs between success and failure.
- **Limits.** What that observation cannot prove without a build or a runtime
  check.

Pick the narrowest useful observation from the
[verification routes](features/README.md). For a shared aspect or default,
check every affected host, not only the machine you are working on. Get the host
list from the flake instead of copying one from somewhere else.

## Run the check and compare

Run the probe on the actual checkout and compare the result with the claim. A
zero exit status or a derivation path does not show the intended behavior. If
the change could cause a regression, also check an unaffected host or the
previous value.

For uncommitted changes, verify the working tree locally. CI validates a
committed revision, not uncommitted edits. Flake evaluation includes a new Nix
file only if Git tracks it, so check the working tree status before you claim
that a successful evaluation covers newly created files. When a PR exists, check
CI for its exact head before you repeat expensive checks.

Use the existing focused tests in [modules/checks.nix](../../../modules/checks.nix)
or in nearby test files. Do not duplicate the whole CI matrix.

If evaluation fails, read the error, the source diff, and the aspect
composition before you touch inputs or the lockfile. Never update `flake.lock`
as a side effect of verification.

Prefer evaluation and targeted generated outputs. Build a single package or Home
Manager activation output only when you must inspect its contents. Build a full
system closure only as a last resort, when activation is imminent and CI cannot
give the proof you need. Keep to the host-wide Nix `max-jobs` and `cores`
limits, and do not override them.

## Report

State the claim, the checked revision or working tree state, the affected hosts,
the exact commands, the observed values, the expected values, and whether the
check passed. Name any hosts you skipped and any effects you did not verify.
CI's stubbed host evaluation is not a native system build.

Temporary logs are optional for quick evaluations. Keep build failure output
when you need it, and do not delete unrelated `result` links or store paths.

Do not deploy, activate, use `--dry-activate`, or change remote host state. For
authorized activation and live service checks, use
[fleet-operations](../fleet-operations/SKILL.md).
