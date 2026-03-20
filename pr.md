## Goal

Refactor a NixOS flake configuration from a traditional `modules/nixos` + `modules/hm` structure to the **vic/den dendritic pattern** using `import-tree` for auto-importing aspects. Achieve 100% feature parity with the old config, then clean up.

## Instructions

- Use the vic/den library with import-tree - all `.nix` files in `modules/aspects/` are auto-imported
- Everything should be an aspect - no separate HM modules or NixOS modules, just aspects with `nixos` and/or `homeManager` blocks
- Folder structure is just for organization - aspect names come from `den.aspects.*` attribute inside files, not paths
- Host aspects have `nixos` (and optionally `homeManager` for host-wide defaults), user aspects have `includes` + `homeManager`
- **Host aspect `homeManager` blocks do NOT propagate to `home-manager.users.<user>`** - only user aspect `homeManager` blocks get forwarded
- User-specific HM config must be in aspects included in the user aspect's `includes`
- Clean up after migration - remove old directories, stale files
- Use `trash put` not `rm` for deletions
- Run `nix fmt` after changes (nixfmt + deadnix via treefmt)

## Discoveries

- **Root cause of all HM packages being missing**: `den.ctx.user.classes = lib.mkDefault [ "homeManager" ]` does NOT propagate to user instances. The correct option is `den.schema.user.classes = lib.mkDefault [ "homeManager" ]`. This single line was why home-manager packages weren't being applied.
- **Host `homeManager` blocks don't propagate to users**: Adding `homeManager` config to a host aspect (e.g., `den.aspects.alpha.homeManager`) does NOT get forwarded to `home-manager.users.<user>`. The vic/den integration only forwards USER aspect `homeManager` blocks via `hm-user → forwardToHost → home-manager.users.<userName>`.
- **User-level HM config must be in user-included aspects**: GUI HM apps, xdg settings, etc. must be in aspects that are in the user aspect's `includes` list, not the host aspect's includes.
- **Dual nature of aspects**: An aspect can have both `nixos` and `homeManager` blocks. If included in a HOST aspect's includes, the `nixos` block applies at OS level but `homeManager` is ignored. If included in a USER aspect's includes, the `homeManager` block applies to HM.
- **Duplicate aspect definitions**: Having the same `den.aspects.*` defined in two files causes conflicts (e.g., `wm.nix` and `gui/wm.nix` both defining `den.aspects.wm`).
- **`osConfig.modules.*` may not exist on all hosts**: Use `(osConfig.modules.timers.enable or false)` to safely check options that only exist on some hosts.
- The `den.hosts.x86_64-linux.alpha.users.repparw = { }` creates the user with default `classes = ["homeManager"]` (from `den.schema.user.classes`).
- The `lib/service-definitions/` files are imported by `services.nix` via `import` (not as NixOS modules).

## Accomplished

**Completed - Full migration with 100% feature parity:**
1. Fixed `den.ctx.user.classes` → `den.schema.user.classes` (root cause of HM not applying)
2. Removed `user-cli`/`user-gui` wrapper aspects, flattened includes in `repparw` user aspect
3. Created `gui/apps.nix` aspect for user-level HM GUI config (foot, imv, obsidian, vesktop, element, anki, godot, scrcpy, pwvucontrol, rquickshare, gtk, mimeApps)
4. Created aspect files under `modules/aspects/cli/` (core, shell, tmux, git, editors, file-manager, scripts, rclone)
5. Created aspect files under `modules/aspects/gui/` (core, browser, wm, kanshi, mpv, obs, spotify, jellyfin-mpv-shim, zathura)
6. Restored ALL missing packages: direnv, nix-direnv, udiskie, wpaperd, rquickshare, obs-backgroundremoval, firefox extension settings, spotify-player keymaps
7. Fixed kanshi to only enable on beta (laptop)
8. Restored `systemd.network.networks` (static IP `192.168.0.18/24` on eth0, DHCP on wlan0)
9. Restored Firefox extension settings (darkreader, sponsorblock, improvedtube), ublock filter lists, missing policies, search engines (IMDb, AI)
10. Restored spotify-player keymaps, actions, and full settings
11. Added OBS NixOS config (enableVirtualCamera, obs-backgroundremoval)
12. Fixed ashell settings and wlsunset systemd service
13. Added missing scripts (t, obs-remux2wsp)
14. Fixed rclone.nix conditional on optional modules
15. Deleted stale files (old wm.nix duplicate, secrets/nixos.nix, treefmt.toml then restored)
16. Restored `formatter.x86_64-linux` in flake outputs (nixfmt + deadnix via treefmt)
17. Updated AGENTS.md and todo.md

**Commits pushed to `feature/den-dendritic`:**
- `9086c2c8` - Full migration (94 files, 3262 insertions, 3900 deletions)
- `34743261` - Cleanup (removed stale files, updated docs)
- `4fed3b1a` - Restore treefmt formatter

## Relevant files / directories

```
flake.nix                              # Main flake (minimal, imports modules, formatter.x86_64-linux)
flake.lock
treefmt.toml                           # nixfmt + deadnix formatter config
AGENTS.md                              # Updated with current structure
todo.md                                # Updated task list
modules/
  den.nix                              # Host/user definitions, aspect includes (REPPARW user aspect)
  aspects/
    auto-upgrade.nix
    gaming.nix
    hyprland.nix
    niri.nix
    nixos-base.nix                     # Base config, overlays, networking, systemd.network.networks
    secrets.nix                        # Sops-nix secrets
    services.nix                       # Podman container services (imports from lib/service-definitions/)
    style.nix
    timers.nix
    virtual-display.nix
    vm.nix
    cli/
      core.nix                         # NixOS: mosh, nh, fish, blueman, pipewire, keyd, openssh
      editors.nix                      # HM: neovim, opencode, ssh, packages
      file-manager.nix                 # HM: yazi
      git.nix                          # HM: git, delta, eza, fd, fzf, gh, zoxide
      rclone.nix                       # HM: cloud storage (conditional on timers)
      scripts.nix                      # HM: custom scripts (media-play-pause, t, obs-remux2wsp, etc.)
      shell.nix                        # HM: fish shell config, direnv, nix-direnv
      tmux.nix                         # HM: tmux config
    gui/
      apps.nix                         # HM: foot, imv, obsidian, vesktop, element, anki, godot, pwvucontrol, scrcpy, rquickshare, wpaperd, gtk, mimeApps
      browser.nix                      # HM: firefox (with darkreader/sponsorblock/improvedtube settings), chromium
      core.nix                         # NixOS: modules.gui, logid, sddm, wshowkeys
      jellyfin-mpv-shim.nix            # HM: jellyfin
      kanshi.nix                       # HM: display profiles (conditional on beta only)
      mpv.nix                          # HM: media player
      obs.nix                          # NixOS: enableVirtualCamera, obs-backgroundremoval + HM: obs-cmd
      spotify.nix                      # HM: spotify-player (keymaps, settings), spotifyd
      wm.nix                           # HM: wayland pkgs, swayidle, swaylock, ashell, wlsunset, rofi, hyprpolkitagent, clipse, swaync
      zathura.nix                      # HM: PDF viewer
lib/
  service-definitions/                 # Podman container definitions (imported by services.nix)
    arr.nix, authelia.nix, changedetection.nix, freshrss.nix,
    jellyfin.nix, ntfy.nix, paperless.nix, proxy.nix
pkgs/
  cfait/default.nix                    # Custom package
  native-client/default.nix            # Custom package
secrets/
  .sops.yaml                           # SOPS age key config
  secrets.yaml                         # Encrypted secrets
```
