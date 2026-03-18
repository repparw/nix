# Todo

## Dendritic Port (COMPLETED)

Ported to den/dendritic pattern using vic/den and import-tree.

### Current Structure
```
flake.nix              # Minimal flake with import-tree + vic/den
modules/
  den.nix              # Host/user definitions + aspect includes
  aspects/            # Feature-centric aspects
    nixos-base.nix   # Base NixOS config
    cli.nix          # CLI tools
    gui.nix          # GUI config
    gaming.nix       # Gaming
    hyprland.nix     # Hyprland WM
    niri.nix         # Niri WM
    secrets.nix       # Sops-nix
    shell-fish.nix   # Fish shell
    user-repparw.nix # User HM config
    vms.nix          # VM config
lib/
  nixos-modules/     # Original modules (for import)
  hm-modules/        # Original HM modules
```

## Pending Tasks

### High Priority
- [ ] Fix podman container services (need secrets)
- [ ] Add health checks for services
- [ ] Document configuration options

### Medium Priority
- [ ] Create backup configuration
- [ ] Add more service aspects
- [ ] Create aspect documentation

### Low Priority
- [ ] Add development container configuration
- [ ] Create module tests
