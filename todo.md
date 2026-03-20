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
    cli/
      core.nix           # NixOS CLI services (mosh, nh, fish, pipewire, etc.)
      editors.nix        # HM: neovim, opencode, ssh, packages
      file-manager.nix   # HM: yazi
      git.nix            # HM: git, delta, eza, fd, fzf, gh, zoxide
      rclone.nix         # HM: cloud storage
      scripts.nix        # HM: custom scripts
      shell.nix          # HM: fish shell, direnv
      tmux.nix           # HM: tmux
    gui/
      apps.nix           # HM: foot, imv, obsidian, vesktop, element, anki, godot, etc.
      browser.nix        # HM: firefox, chromium
      core.nix           # NixOS: logid, sddm, wshowkeys
      jellyfin-mpv-shim.nix
      kanshi.nix         # HM: display profiles (beta only)
      mpv.nix            # HM: media player
      obs.nix            # NixOS+HM: OBS studio
      spotify.nix        # HM: spotify, spotifyd
      wm.nix             # HM: wayland pkgs, swayidle, wlsunset, rofi
      zathura.nix        # HM: PDF viewer
    gaming.nix           # Steam/gamescope
    hyprland.nix         # Hyprland WM
    niri.nix             # Niri WM
    nixos-base.nix       # Base config, overlays, networking, home-manager
    secrets.nix          # Sops-nix
    services.nix         # Podman container services
    style.nix            # Stylix theming
    timers.nix           # Backup/rsync timers
    virtual-display.nix  # Sunshine/Moonlight
    vm.nix               # VM/libvirt
lib/
  service-definitions/   # Container definitions (imported by services.nix)
```

## Pending Tasks

### High Priority
- [ ] Document configuration options

### Medium Priority
- [ ] Create backup configuration
- [ ] Add more service aspects (karakeep, n8n, monitoring, open-webui)
- [ ] Create aspect documentation

### Low Priority
- [ ] Add development container configuration
- [ ] Create module tests
- [ ] Inline lib/service-definitions into services.nix (if desired)
