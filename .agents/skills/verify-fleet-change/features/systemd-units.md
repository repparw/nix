# Generated systemd units

For service, timer, mount, and dependency changes, check the rendered unit. Do
not stop at `services.<name>.enable` evaluating to true.

This example asserts that Alpha's offsite backup service is a one-shot unit:

```sh
nix eval --raw --no-update-lock-file '.#nixosConfigurations.alpha.config.systemd.units."restic-backups-offsite.service".text' | grep -Fx 'Type=oneshot'
```

The command fails when the expected service type is absent. Replace the host,
unit name, and assertion with the behavior you need to verify, including
`ExecStart`, `ExecStartPre`, `After`, `Requires`, `Environment`, or timer
fields. If an ordering change spans multiple lines, compare the relevant
fields together rather than matching a single keyword. Check another host if
the aspect composes differently there.

The rendered text shows what systemd would receive from this configuration. It
does not show that the dependencies exist at runtime, that the unit starts, or
that the service succeeds. If correctness depends on execution or failure paths,
pick the closest [focused check](focused-checks.md) and read its assertions
before you run it.
