# Generated systemd units

For service, timer, mount, and dependency changes, check the rendered unit. Do
not stop at `services.<name>.enable` evaluating to true.

This example prints the offsite backup service on a selected host:

```sh
nix eval --raw --no-update-lock-file '.#nixosConfigurations.alpha.config.systemd.units."restic-backups-offsite.service".text'
```

Change the host and quoted unit name for your task. Inspect the fields that
matter, such as `ExecStart`, `ExecStartPre`, `After`, `Requires`, `Environment`,
or timer fields, and compare them with the intended behavior. For agentic
validation, assert the exact expected value or ordering instead of simply
printing the unit. Check another host if the aspect composes differently there.

The rendered text shows what systemd would receive from this configuration. It
does not show that the dependencies exist at runtime, that the unit starts, or
that the service succeeds. If correctness depends on execution or failure paths,
pick the closest [focused check](focused-checks.md) and read its assertions
before you run it.
