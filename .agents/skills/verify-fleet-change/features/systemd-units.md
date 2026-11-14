# Generated systemd units

For service, timer, mount, and dependency changes, check the rendered unit. Do
not stop at `services.<name>.enable` evaluating to true.

This example prints the offsite backup service on a selected host:

```sh
nix eval '.#nixosConfigurations.alpha.config.systemd.units."restic-backups-offsite.service".text' --raw --no-update-lock-file
```

Change the host and the quoted unit name for your task. Read the fields that
matter, such as `ExecStart`, `ExecStartPre`, `After`, `Requires`, `Environment`,
or the timer fields, and compare them with the intended behavior. Check a second
host if the same aspect composes differently there.

The rendered text shows what systemd would receive from this configuration. It
does not show that the dependencies exist at runtime, that the unit starts, or
that the service succeeds. If correctness depends on execution or failure paths,
pick the closest [focused check](focused-checks.md) and read its assertions
before you run it.
