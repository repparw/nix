# home-manager-files

## Sub-features

- `~/.config/opencode/opencode.json` generated with the agent models from
  `modules/aspects/ai/opencode.nix`
- Other generated dotfiles under `home-files/` match their module sources
- The new generation is what a switch would actually activate

## How to get to it (user POV)

The user changed a module that writes a config file (e.g. added a pstack
agent). Eval passing is not enough — a merge or override could drop the value.
The generated file is the truth the switch will install.

## Driving it with nix build + read

```bash
nix build .#nixosConfigurations.alpha.config.home-manager.users.repparw.home.activationPackage --no-link
GEN=$(readlink -f result)/home-files/.config/opencode/opencode.json
jq -r '.agent | to_entries[] | "\(.key): \(.value.model)"' "$GEN"
```

Expect the exact key/value set from the module (15 agents as of 2026-09-01,
e.g. `swarm-workers-orca: orcarouter/deepseek/deepseek-v4-flash-free`).
Capture the jq output as evidence.

## Gotchas

- `result` is a shared symlink at repo root — another build may repoint it;
  resolve with `readlink -f` immediately after building and copy what you need.
- Files live under `home-files/<path-in-$HOME>` inside the result, not at the
  top level.
- This does NOT validate system-level (non-home) config — use
  [system-build](system-build.md) for that.
