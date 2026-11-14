# Effective options and host coverage

For an option or aspect change, start with the value you expect, the hosts it
applies to, and a control host that should not change.

List the hosts:

```sh
nix eval .#nixosConfigurations --apply builtins.attrNames --json --no-update-lock-file
```

Query the effective option, not just its declaration in the source. This example
reads the fleet's host name:

```sh
nix eval '.#nixosConfigurations.alpha.config.networking.hostName' --raw --no-update-lock-file
```

For a Home Manager option, evaluate the nested configuration. This is cheaper
than building an activation package:

```sh
nix eval '.#nixosConfigurations.alpha.config.home-manager.users.repparw.programs.opencode.settings.agent' --json --no-update-lock-file
```

Replace the host and option with your target. Compare the result with the
behavior you expect, not with an earlier printout.

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
