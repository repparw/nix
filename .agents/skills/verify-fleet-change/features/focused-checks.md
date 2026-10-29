# Existing tests and build evidence

Find the test closest to the behavior being changed. Start from
[modules/checks.nix](../../../../modules/checks.nix) and the task's adjacent
`_tests` or `.test` source. Read the assertions to establish what the
check really observes; do not infer coverage from a check's name.

For example, the fleet monitoring check is already exposed through the
flake's checks output:

~~~sh
nix build '.#checks.x86_64-linux.monitoring-fleet' --no-link --no-update-lock-file --print-out-paths
~~~

This runs the existing check on a compatible build host. Substitute the
relevant check and system for the task; do not assume the execution machine
can build every architecture or run KVM tests. When a test uses mocks,
stubs, or disposable VMs, report those boundaries explicitly.

Before inventing a second test harness, extend an existing one with a
counterexample that fails when the intended behavior is removed. A passing
test then supports that specific claim, not every property of the fleet.

If no existing test covers a critical behavior, report the gap rather than
claiming that evaluation or a package build proves it. Actual activation
and remote state changes belong to
[fleet-operations](../../fleet-operations/SKILL.md).
