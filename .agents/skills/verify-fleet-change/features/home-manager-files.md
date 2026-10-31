# Generated Home Manager files

Evaluate the relevant Home Manager option first using
[effective values](effective-values.md). Build an activation output only when
the claim concerns the final serialized file, path, or ownership of generated
configuration.

For example, to inspect the generated OpenCode JSON on Alpha:

```sh
home_output=$(nix build '.#nixosConfigurations.alpha.config.home-manager.users.repparw.home.activationPackage' --no-link --no-update-lock-file --print-out-paths)
jq '.agent' "$home_output/home-files/.config/opencode/opencode.json"
```

Replace the host, user, target file, and JSON query with the effect being
verified. Compare the generated contents against the claimed behavior; do
not accept merely obtaining a store path.

The command realizes a Home Manager output and can be expensive. Preserve
any useful error output if it fails. Do not build the entire NixOS system
only to inspect a generated home file. This does not prove that the file
was activated in the user's actual home directory.
