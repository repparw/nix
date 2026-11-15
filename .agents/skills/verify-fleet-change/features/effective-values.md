# Effective options and host coverage

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

For a Home Manager option, evaluate the nested configuration and assert the
expected value. This is cheaper than building an activation package:

```sh
nix eval --json --no-update-lock-file '.#nixosConfigurations.alpha.config.home-manager.users.repparw.programs.opencode.settings.permission' | jq -e '."browse_*"."*" == "ask"'
```

These examples fail if the expected hostname or permission is absent.
Replace the host, option, and expected value with the specific behavior the
change is meant to produce. A command that only prints a value is not a
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
