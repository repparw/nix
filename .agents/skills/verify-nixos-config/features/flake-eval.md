# flake-eval

## Sub-features

- Flake evaluates for every host: `alpha`, `epsilon`, `pi`, `pi-sd`
- Module options under `home-manager.users.repparw.programs.*` hold intended values
- `den.aspects` composition (includes/defaults) resolves without conflicts

## How to get to it (user POV)

The user edits `modules/aspects/**` and wants to know: does the flake still
evaluate, and did my option land where I think it did?

## Driving it with nix eval

```bash
# Host exists and evaluates
nix eval .#nixosConfigurations.alpha.config.system.nixos.release --raw && echo

# Option holds intended value (path mirrors the module's settings tree)
nix eval .#nixosConfigurations.alpha.config.home-manager.users.repparw.programs.opencode.settings.agent --json | jq
```

For options you cannot name yet, walk the tree:

```bash
nix eval .#nixosConfigurations.alpha.config.home-manager.users.repparw.programs --json | jq 'keys'
```

## Gotchas

- Repo convention: generated aspects are configured via `den.aspects.<name>`,
  not `imports` — if your eval shows the default value, check whether an
  aspect include or `modules/defaults.nix` overrides yours.
- Store eval output as evidence per SKILL.md (`/tmp/nix-verify/`).
