# Existing tests and build evidence

Find the test closest to the behavior you changed. Start from
[modules/checks.nix](../../../../modules/checks.nix) and the `_tests` or `.test`
source next to the code. Read the assertions to see what the check actually
observes. Do not guess its coverage from its name.

For example, the fleet monitoring check is already in the flake's checks output:

```sh
nix build '.#checks.x86_64-linux.monitoring-fleet' --no-link --no-update-lock-file --print-out-paths
```

This runs the existing check on a compatible build host. Substitute the check
and system for your task. Do not assume the machine you are on can build every
architecture or run KVM tests. If a test uses mocks, stubs, or disposable VMs,
say so in your report.

Before you write a second test harness, extend an existing one with a
counterexample that fails when you remove the intended behavior. A passing test
then supports that specific claim, and not every property of the fleet.

If no existing test covers a critical behavior, report the gap. Do not claim
that evaluation or a package build proves it. Activation and remote state
changes belong to [fleet-operations](../../fleet-operations/SKILL.md).
