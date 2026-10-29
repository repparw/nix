# Generated systemd units

For service, timer, mount, and dependency changes, verify the **rendered unit**
rather than merely checking that `services.<name>.enable` evaluates to true.

For example, inspect the offsite backup service from a selected host:

~~~sh
nix eval '.#nixosConfigurations.alpha.config.systemd.units."restic-backups-offsite.service".text' --raw --no-update-lock-file
~~~

Change the host and quoted unit name for the task. Read the relevant
`ExecStart`, `ExecStartPre`, `After`, `Requires`, `Environment`, or
timer fields as appropriate, and compare them with the intended behavior.
Check a second host if the same aspect is composed differently there.

Rendered text proves what systemd would receive from this configuration;
it does not prove that dependencies exist at runtime, the unit starts, or
the service succeeds. If correctness depends on execution or failure paths,
select the closest [focused check](focused-checks.md) and inspect its actual
assertions before running it.
