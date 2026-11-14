# Generated Home Manager files

Start by evaluating the effective Home Manager option, without building an
activation package. For example, to inspect OpenCode's configured settings:

```sh
nix eval --json --no-update-lock-file '.#nixosConfigurations.alpha.config.home-manager.users.repparw.programs.opencode.settings.permission' | jq -e '."browse_*"."*" == "ask"'
```

The assertion fails if the configured permission is missing. It checks the
option value, not necessarily the serialized file. Home Manager
may add defaults, merge other options, or transform values when writing the file.
For example, OpenCode can merge MCP servers and add a JSON schema.

If the claim concerns the **exact generated contents**, build only the target
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
application loaded it. For ownership, activation, and runtime behavior, check
the appropriate evidence separately.
