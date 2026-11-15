# Validation examples

Choose the cheapest observation that can falsify your claim. These commands
check the proposed configuration in the checkout. They do not prove that a
host activated it or that an application works at runtime.

## Effective Nix options

For an option or aspect change, start with the value you expect, the hosts it
applies to, and a control host that should not change.

List the hosts:

```sh
nix eval .#nixosConfigurations --apply builtins.attrNames --json --no-update-lock-file
```

Query the effective option, not just its declaration in the source. This example
asserts Alpha's host name:

```sh
test "$(nix eval --raw --no-update-lock-file '.#nixosConfigurations.alpha.config.networking.hostName')" = alpha
```

The assertion fails when the expected value is absent. Replace the host,
option, and expected value with the behavior the change is meant to produce. A command that only prints a value is not a
regression test.

For a change to shared defaults or aspect composition, check the relevant option
on each affected host. Evaluating the toplevel derivation path catches
evaluation failures, but it does not prove the changed option, a native build,
or runtime behavior:

```sh
nix eval '.#nixosConfigurations.alpha.config.system.build.toplevel.drvPath' --raw --no-update-lock-file
```

If the effective value disagrees with your source change, trace the aspect's
`includes` and `provides` composition and `modules/defaults.nix`. Do this before
you change the flake lock or add a workaround.

## Generated systemd units

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
pick the closest focused check below and read its assertions
before you run it.

## Generated Home Manager files

Start by evaluating the effective Home Manager option, without building an
activation package. For example, to inspect OpenCode's configured settings:

```sh
nix eval --json --no-update-lock-file '.#nixosConfigurations.alpha.config.home-manager.users.repparw.programs.opencode.settings.permission' | jq -e '."browse_*"."*" == "ask"'
```

The assertion fails if the configured permission is missing. It checks the
option value, not necessarily the serialized file. Home Manager
may add defaults, merge other options, or transform values when writing the file.
For example, OpenCode can merge MCP servers and add a JSON schema.

If the claim concerns the exact generated contents, build only the target
file's `source` and assert properties of the resulting JSON:

```sh
jq -e '."$schema" == "https://opencode.ai/config.json" and .permission["browse_*"]["*"] == "ask"' "$(nix build --no-link --print-out-paths --no-update-lock-file '.#nixosConfigurations.alpha.config.home-manager.users.repparw.xdg.configFile."opencode/home-manager.json".source')"
```

OpenCode uses `opencode/home-manager.json` here because
`programs.opencode.mutableSettings = true`. The `source` output is a single
file in the Nix store, not a directory containing `home-files`. The example
checks the generated schema and effective permission. For another
generated file, replace the host, user, and `xdg.configFile` entry. When a file
has an inline `text` option instead of a generated `source`, query its effective
`text` directly with `nix eval --raw` and skip the build.

This builds far less than the full Home Manager activation output. It still does
not prove that Home Manager activated the file at its target path, or that the
application loaded it. Check ownership and activation on the host after an authorized activation,
and check runtime behavior in the application.

## Focused tests and package builds

Find the test closest to the behavior you changed. Start from
[modules/checks.nix](../../../modules/checks.nix) and the `_tests` or `.test`
source next to the code. Read the assertions to see what the check actually
observes. Do not guess its coverage from its name.

For example, the fleet monitoring check is already in the flake's checks output:

```sh
nix build --no-link --no-update-lock-file '.#checks.x86_64-linux.monitoring-fleet'
```

The command fails if the check cannot build or its assertions fail. Substitute the check
and system for your task. Do not assume the machine you are on can build every
architecture or run KVM tests. If a test uses mocks, stubs, or disposable VMs,
say so in your report.

Before you write a second test harness, extend an existing one with a
counterexample that fails when you remove the intended behavior. A passing test
then supports that specific claim, and not every property of the fleet.

If no existing test covers a critical behavior, report the gap. Do not claim
that evaluation or a package build proves it. Activation and remote state
changes belong to [fleet-operations](../fleet-operations/SKILL.md).
