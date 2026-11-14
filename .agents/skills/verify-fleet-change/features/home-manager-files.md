# Generated Home Manager files

First evaluate the Home Manager option, as described in
[effective values](effective-values.md). Build an activation output only when
the claim is about the final serialized file, its path, or its ownership.

This example reads the generated OpenCode JSON on Alpha:

```sh
home_output=$(nix build '.#nixosConfigurations.alpha.config.home-manager.users.repparw.home.activationPackage' --no-link --no-update-lock-file --print-out-paths)
jq '.agent' "$home_output/home-files/.config/opencode/opencode.json"
```

Replace the host, user, target file, and JSON query with the effect you are
verifying. Compare the file contents with the claimed behavior. Getting a store
path does not prove anything.

The build realizes a Home Manager output and can be expensive. Keep the error
output if it fails. Do not build the whole NixOS system just to read a generated
home file. The result does not show that activation placed the file in the
user's real home directory.
