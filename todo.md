# Todo

## Dendritic Port (COMPLETED)

Ported to den/dendritic pattern using vic/den and import-tree.

### Current Structure
```
flake.nix                # Minimal flake with import-tree + vic/den
modules/
  den.nix                # Host/user definitions + aspect includes
  aspects/               # Feature-centric aspects
    auto-upgrade.nix     # Automatic flake updates
    cli.nix              # CLI tools
    gaming.nix           # Gaming
    gui.nix              # GUI config
    hyprland.nix         # Hyprland WM
    niri.nix             # Niri WM
    nixos-base.nix       # Base NixOS config (includes overlays, home-manager config)
    secrets.nix          # Sops-nix
    services.nix         # Podman container services
    shell-fish.nix       # Fish shell
    style.nix            # Stylix theming
    timers.nix           # Backup/rsync timers
    user-repparw.nix     # User HM config
    virtual-display.nix  # Sunshine/Moonlight virtual display
    vm.nix               # VM setup
lib/
  service-definitions/   # Container definitions (imported by services.nix)
pkgs/
  cfait/                 # cfait package (from nixpkgs-pr)
  native-client/         # native-client package
```

## Pending Tasks

### High Priority
- [x] Fix podman container services (need secrets)
- [x] Add health checks for services
- [x] Achieve feature parity with main
- [ ] Document configuration options

### Medium Priority
- [ ] Create backup configuration
- [ ] Add more service aspects (karakeep, n8n, monitoring, open-webui)
- [ ] Create aspect documentation

### Low Priority
- [ ] Add development container configuration
- [ ] Create module tests
- [ ] Inline lib/ modules into aspects (if desired)
