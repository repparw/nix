# AGENTS.md - NixOS Configuration Repository

This repository contains repparw's personal NixOS system configurations using the Nix Flake system.

## Project Overview

- **Type**: NixOS flake configuration with Home Manager
- **Systems**: `alpha` (desktop), `beta` (laptop)
- **Structure**: `flake.nix` → `systems/`, `modules/`, `overlays/`, `home/`, `secrets/`

---

## Build Commands

### Rebuild System
```bash
sudo nixos-rebuild switch --flake .#alpha
sudo nixos-rebuild switch --flake .#beta
```

### Build-only (no switch)
```bash
sudo nixos-rebuild build --flake .#alpha
```

### Eval Configuration
```bash
# Check configuration evaluates without building
nix eval .#nixosConfigurations.alpha.config.system.build.toplevel.outPath
```

### Update Flake Inputs
```bash
nix flake update
```

---

## Lint/Format Commands

### Format Code
```bash
nix fmt
```
This uses `nixfmt-tree` as defined in `flake.nix:117`.

### Check Nix Evaluation
```bash
nix eval .#nixosConfigurations.alpha.pkgs.system --impure
```

### Check for Updates
```bash
nix flake info
nix flake metadata
```

---

## Secrets Management

Secrets are managed via **sops-nix** and stored in `secrets/`.

- DO NOT commit raw secret values
- Use `sops` to edit encrypted secrets
- The secrets directory contains `.sops.yaml` and age keys

Example workflow for adding a new secret:
```bash
# Edit secrets (requires proper age key)
sops secrets/service-name.yaml
```

---

## Code Style Guidelines

### File Organization
- **Systems**: `systems/<hostname>/default.nix` - host-specific config
- **Modules**: `modules/nixos/` and `modules/hm/` - reusable modules
- **Overlays**: `overlays/default.nix` - package overlays
- **Home**: `home/<hostname>.nix` - Home Manager user config

### Nix Language Conventions

1. **Attribute Sets**: Use curly braces for multi-line attribute sets
   ```nix
   config = {
     option1 = true;
     option2 = "value";
   };
   ```

2. **Lists**: Use inline syntax for short lists, multi-line for long ones
   ```nix
   shortList = [ a b c ];

   longList = [
     "first"
     "second"
     "third"
   ];
   ```

3. **Let Bindings**: Use `let ... in` for local definitions
   ```nix
   let
     pkgsDir = ../pkgs;
     mkPkg = name: final: prev: { ${name} = final.callPackage ...; };
   in
   { ... }
   ```

4. **Imports**: Always use relative paths with `./` or `../`
   ```nix
   imports = [ ./default.nix ];
   ```

5. **Function Arguments**: Use `{ ... }:` pattern for module arguments
   ```nix
   { config, pkgs, inputs, ... }:
   ```

6. **Trailing Commas**: Always use trailing commas (Nix is tolerant but this is idiomatic)

### Naming Conventions

- **Files**: `kebab-case.nix` (e.g., `auto-upgrade.nix`, not `autoUpgrade.nix`)
- **Options**: Follow NixOS option naming (e.g., `services.foo.enable`)
- **Variables**: `camelCase` for local variables, `kebab-case` for attribute names
- **Modules**: Use descriptive names (e.g., `services/nginx.nix`)

### Formatting Rules

- **Indentation**: 2 spaces (Nix standard)
- **Line Length**: Prefer lines under 80 chars when practical
- **Spacing**: Space after `=` in bindings, no space before `=` in attributes
- **Comments**: Use `#` for comments; avoid unnecessary comments

### Imports Pattern

```nix
# At top of file for module imports
{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/services
  ];
  
  # ... configuration
}
```

### Error Handling

- Use `lib.mkIf` for conditional options (not `if then else` in attribute sets)
- Use `lib.mkMerge` for merging lists/attrs across modules
- Validate paths exist with `lib.pathExists` or `builtins.pathExists`

### Package Overlays

Add custom packages in `pkgs/<name>/default.nix`, then reference in `overlays/default.nix`:
```nix
mkPkgOverlay = name: final: prev: {
  ${name} = final.callPackage (pkgsDir + "/${name}") { };
};
```

### Testing Changes

1. **Quick eval check**: `nix eval .#nixosConfigurations.alpha.pkgs.system --impure`
2. **Dry build**: `sudo nixos-rebuild build --flake .#alpha`

---

## Important Files

| File | Purpose |
|------|---------|
| `flake.nix` | Main flake entry, defines outputs, packages, VMs |
| `systems/alpha/default.nix` | Desktop system config |
| `systems/beta/default.nix` | Laptop system config |
| `modules/nixos/default.nix` | Shared NixOS configuration |
| `modules/hm/default.nix` | Shared Home Manager config |
| `overlays/default.nix` | Package overlays |
| `secrets/nixos.nix` | SOPS secrets integration |

---

## Common Tasks

### Add New System Package
1. Add to `modules/nixos/default.nix` in `environment.systemPackages` OR
2. Add to `modules/nixos/cli/default.nix` or `modules/nixos/gui/default.nix`

### Add New Home Manager Package
1. Add to appropriate `modules/hm/cli/` or `modules/hm/gui/` module

### Add New Service (Podman containers)
1. Create `modules/nixos/services/<service>.nix`
2. Import in `modules/nixos/services/default.nix`
3. Enable in system config

### Add User Program
1. Create module in `modules/hm/cli/` or `modules/hm/gui/`
2. Import in appropriate `modules/hm/cli/default.nix` or `modules/hm/gui/default.nix`
