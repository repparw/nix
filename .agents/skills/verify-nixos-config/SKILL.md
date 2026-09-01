---
name: verify-nixos-config
description: Prove NixOS flake config changes are correct without switching — eval, build home files, diff against the running system. Use before asking for `sudo nh os switch`, after editing modules/, or when a rebuild surprises you.
---

# Verify NixOS config (flake `~/Projects/nix`)

The "app" is the NixOS flake in this repo. A user "runs" it by switching
(`sudo nh os switch .`, password required — agents cannot run it). Everything
an agent can verify happens **without** the switch: evaluate, build, diff.

Hosts: `alpha` (this machine), `epsilon`, `pi`, `pi-sd`. Default to `alpha`
unless the change is host-specific elsewhere. `$HOST` below means the target
host name.

## Launch

No long-running process. "Launching" means building the config under test:

```bash
# Full system closure (heavy, minutes — cached after first run)
nix build .#nixosConfigurations.$HOST.config.system.build.toplevel --no-link

# Home-manager files only (much lighter — use for dotfile/config changes)
nix build .#nixosConfigurations.$HOST.config.home-manager.users.repparw.home.activationPackage --no-link
```

Ready when the command exits 0 and `./result` symlinks into the store.
Teardown: `rm -f result` (the `result` symlink is gitignored scratch; store
paths stay in /nix/store and are garbage, not live).

## Doctor

Run this first when anything looks off — it answers "is this checkout worth
driving?" without building anything:

```bash
nix eval .#nixosConfigurations.$HOST.config.system.nixos.release --raw && echo
```

Expect exit 0 and a release string (e.g. `26.11`). Failures mean: flake eval
error (check `git stash` vs HEAD to see if your edit caused it), wrong host
name (valid hosts via `nix eval .#nixosConfigurations --apply builtins.attrNames`),
or a corrupted flake.lock (try `nix flake update --lock-only` dry check).

## Drive

### Feature: flake evals (see features/flake-eval.md)

```bash
nix eval .#nixosConfigurations.$HOST.config.home-manager.users.repparw.<option path> --json
```

Walk the option tree under `config.` for the module you touched. Example that
proves the pstack bridge (options live under
`programs.opencode.settings.agent.<name>.model`):

```bash
nix eval .#nixosConfigurations.alpha.config.home-manager.users.repparw.programs.opencode.settings.agent --json | jq -r 'to_entries[] | "\(.key): \(.value.model)"'
```

### Feature: generated home files match intent (see features/home-manager-files.md)

```bash
nix build .#nixosConfigurations.$HOST.config.home-manager.users.repparw.home.activationPackage --no-link
grep -n '"model"' "$(readlink -f result)/home-files/.config/opencode/opencode.json"
```

The generated file is authoritative — checking the eval is not enough when a
module merge (`den.aspects`) can override your value.

### Feature: closure diff vs running system (see features/closure-diff.md)

```bash
nix store diff-closures /run/current-system ./result
```

Reads as package/version deltas the switch would apply. Empty on a no-op
rebuild; every line is a change a switch would make.

## Evidence

Write proofs to `/tmp/nix-verify/`:

- `eval-$HOST-$OPTION.json` — eval output for the option you drove
- `closure-diff-$HOST.txt` — diff-closures output
- `build-$HOST.log` — build output tail on failure

Proof standard: an eval or a successful build alone is weak. For any generated
file the change targets, **read the generated file from the store** (drive
feature 2) and capture the relevant lines. State in your final message which
feature file you drove; a proof that skips the generated-file check is
incomplete when the map lists it.

## Cleanup

Only `rm -f result` and your scratch files under `/tmp/nix-verify/` when a run
failed before producing evidence. Never delete store paths, never touch
`/run/current-system`, never run the switch yourself — switching needs the
user's password and is their call. Evidence in `/tmp/nix-verify/` survives
cleanup; cleanup exists only for aborted runs.
