# system-build

## Sub-features

- `nixosConfigurations.<host>.config.system.build.toplevel` builds to a store path
- New modules/options typecheck during build (eval-only gaps surface here)
- Pre-commit hooks (deadnix, nixfmt, convco) stay green on committed code

## How to get to it (user POV)

The user is about to run `sudo nh os switch .` and wants certainty the switch
won't fail midway leaving a half-applied generation. A successful toplevel
build is that certainty.

## Driving it with nix build

```bash
nix build .#nixosConfigurations.alpha.config.system.build.toplevel --no-link --print-build-logs 2>&1 | tee /tmp/nix-verify/build-alpha.log
```

Exit 0 + `./result` symlink = buildable. On failure, the log tail names the
failing derivation and option.

## Gotchas

- Minutes-long on first run or after a channel bump; cached otherwise. Prefer
  the lighter features unless a system-level module changed.
- The build runs the user's rebuild user-privately — no sudo involved, nothing
  is activated. `nixos-rebuild test`/`switch` are out of scope for agents.
- If the failure is an eval error, drop back to
  [flake-eval](flake-eval.md) to localize it before rebuilding.
