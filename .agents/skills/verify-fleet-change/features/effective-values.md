# Effective options and host coverage

For an option or aspect change, start with the expected value, the applicable
host(s), and an unchanged control host when relevant.

Discover available hosts:

~~~sh
nix eval .#nixosConfigurations --apply builtins.attrNames --json --no-update-lock-file
~~~

Query the **effective** option rather than only reading its source declaration.
For example, the fleet's host identity:

~~~sh
nix eval '.#nixosConfigurations.alpha.config.networking.hostName' --raw --no-update-lock-file
~~~

For a Home Manager option, evaluate the nested configuration; this is cheaper
than building an activation package:

~~~sh
nix eval '.#nixosConfigurations.alpha.config.home-manager.users.repparw.programs.opencode.settings.agent' --json --no-update-lock-file
~~~

Replace the host and option with the task's target. Compare the returned
value to the expected behavior, not just to an earlier printed value.

For changes to shared defaults or aspect composition, check each affected
host's relevant option. Evaluating the toplevel derivation path also catches
configuration evaluation failures but does **not** prove the changed option,
a native build, or runtime behavior:

~~~sh
nix eval '.#nixosConfigurations.alpha.config.system.build.toplevel.drvPath' --raw --no-update-lock-file
~~~

If the effective value disagrees with the source change, trace the aspect's
`includes`/`provides` composition and `modules/defaults.nix` before
altering the flake lock or adding a workaround.
