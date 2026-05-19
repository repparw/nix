# AGENTS.md

Repo follows upstream `vic/den` default-template structure.

## Core Rules

- Declare hosts and users centrally in `modules/hosts.nix`.
- Let Den generate host and user aspects from that inventory.
- Configure generated aspects through `den.aspects.<name>`.
- Use `includes` for aspect composition.
- Use `imports` only for real Nix module imports.
- Put repo-wide defaults in `modules/defaults.nix` via `den.default`.
- Keep concern-specific flake inputs next to module or aspect that uses them.
- Use mutual providers for host and user crossover config.

## File Roles

- `flake.nix`: bootstrap only.
- `modules/dendritic.nix`: core flake wiring and base shared inputs.
- `modules/defaults.nix`: global defaults and baseline includes.
- `modules/vm.nix`: VM launchers.
- `modules/hosts/<host>.nix`: host-specific NixOS config.
- `modules/aspects/<user>.nix`: user composition and Home Manager bridge.
- `modules/aspects/cli/*.nix`, `modules/aspects/gui/*.nix`: reusable user-facing features.

## Placement Rules

- Keep host specifics in host aspects.
- Keep user specifics in user aspects.
- Put reusable features in dedicated aspect files.
- Prefer named shared stacks like `den.aspects.cli` and `den.aspects.gui` over repeating lists.
- Prefer one aspect per file.

## Patterns

- Use `den.default` for values that should apply everywhere unless overridden.
- Use `${user}.provides.${host}` for user-owned config that must land on host side.
- Use `${host}.provides.${user}` for host-owned config that must land on user side.
- Prefer `lib.mkIf` and `lib.mkMerge` for conditional config.
- Do not put plaintext secrets in repo; use `sops-nix`.

## Validation

### nh os repl

Load a NixOS system configuration in an interactive REPL:
```shell
nh os repl
```

With no argument it loads my nix config at ~/code/nix

Then you can check e.g:
```nix
nix-repl> config.services.tailscale
{
  authKeyParameters = { ... };
  derper = { ... };
  enable = true;
  extraDaemonFlags = [ ... ];
  package = «derivation /nix/store/...-tailscale-1.94.2.drv»;
  ...
}
```

Useful after structural changes:

```shell
nix fmt
nix flake check
```

When adding new files or directories, stage them with `git add` before evaluating. Nix flakes only see tracked files, so untracked changes will not be picked up and may cause attribute-missing errors.

To verify a specific host builds to a derivation:

```shell
nix eval .#nixosConfigurations.alpha.config.system.build.toplevel.outPath
```
