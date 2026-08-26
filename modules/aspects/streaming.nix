{
  den,
  lib,
  ...
}:
{
  den.aspects.streaming.nixos =
    {
      config,
      pkgs,
      ...
    }:
    let
      user = "repparw";

      moonshine-boxart = pkgs.runCommand "moonshine-boxart" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
        mkdir -p $out
        rsvg-convert \
          --width 512 \
          --height 512 \
          ${pkgs.niri.src}/docs/wiki/logo/niri-icon.svg \
          > $out/desktop.png
        cp ${pkgs.steam-unwrapped}/share/icons/hicolor/256x256/apps/steam.png $out/steam.png
        rsvg-convert \
          --width 512 \
          --height 512 \
          ${pkgs.heroic}/share/icons/hicolor/scalable/apps/com.heroicgameslauncher.hgl.svg \
          > $out/heroic.png
      '';

      moonshine-desktop = pkgs.writeShellApplication {
        name = "moonshine-desktop";
        runtimeInputs = [ pkgs.niri ];
        text = ''
          # Run a nested, isolated Niri desktop on Moonshine's Wayland output.
          # Do not use --session: this is not the user's primary compositor.
          exec niri
        '';
      };

      moonshine-steam = pkgs.writeShellApplication {
        name = "moonshine-steam";
        runtimeInputs = [
          pkgs.bubblewrap
          pkgs.procps
          # Use the NixOS-configured wrapper so extraCompatPackages (GE-Proton)
          # is exported to Steam inside Moonshine's transient session too.
          config.programs.steam.package
        ];
        text = ''
          # Steam is single-instance per user. Stop the desktop instance so it
          # cannot steal Big Picture from Moonshine's private compositor.
          if pgrep -x steam >/dev/null; then
            steam -shutdown >/dev/null 2>&1 || true
            for _ in $(seq 1 30); do
              pgrep -x steam >/dev/null || break
              sleep 1
            done
          fi

          # Expose the moonshine-wsi implicit layer to Steam and Proton.
          # System Vulkan loaders find it via /run/opengl-driver (wired up by
          # the module's hardware.graphics.extraPackages), but Steam's runtime
          # container never sees that path; Proton discovers implicit layers
          # through forwarded host XDG_DATA_DIRS.
          export XDG_DATA_DIRS="${config.services.moonshine.package}/share:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

          # Keep Steam from probing these automount paths and waking the disks.
          exec bwrap \
            --dev-bind / / \
            --tmpfs /mnt/seagate \
            --tmpfs /home/containers/media/seagate \
            -- steam steam://open/bigpicture
        '';
      };

      # HDR needs gamescope's own WSI layer so clients can present HDR surfaces
      # to gamescope; nixpkgs disables it by default.
      gamescopeHdr = pkgs.gamescope.override { enableWsi = true; };

      moonshine-steam-gamescope-hdr = pkgs.writeShellApplication {
        name = "moonshine-steam-gamescope-hdr";
        runtimeInputs = [
          gamescopeHdr
          pkgs.procps
          # Use the NixOS-configured wrapper so extraCompatPackages (GE-Proton)
          # is exported to Steam inside Moonshine's transient session too.
          config.programs.steam.package
        ];
        text = ''
          # Steam is single-instance per user. Stop the desktop instance so it
          # cannot steal Big Picture from Moonshine's private compositor.
          if pgrep -x steam >/dev/null; then
            steam -shutdown >/dev/null 2>&1 || true
            for _ in $(seq 1 30); do
              pgrep -x steam >/dev/null || break
              sleep 1
            done
          fi

          # Gamescope's WSI layer must stay discoverable for clients
          # presenting into gamescope; same XDG_DATA_DIRS forwarding as the
          # plain Big Picture entry above. moonshine-wsi is force-disabled
          # below.
          export XDG_DATA_DIRS="${config.services.moonshine.package}/share:${gamescopeHdr}/share:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

          # Test workaround for hgaiser/moonshine#93 (HDR/DX11 black screen):
          # wrap Steam in Gamescope at the client's resolution. Gamescope owns
          # the surface Moonshine's compositor sees, so games present to
          # Gamescope instead of creating their own (HDR 1x1) WSI swapchain.
          w=''${MOONSHINE_CLIENT_WIDTH:-1920}
          h=''${MOONSHINE_CLIENT_HEIGHT:-1080}
          rate=''${MOONSHINE_CLIENT_FRAMERATE:-60}

          # The moonshine-wsi Vulkan layer breaks gamescope (a compositor, not
          # a game): it redirects swapchains into Moonshine's WSI path. Games
          # inside gamescope present to gamescope's own compositor, and
          # gamescope presents to Moonshine as a plain Wayland client, so the
          # layer is not needed here. Disable it for the whole gamescope session
          # (DISABLE_* takes precedence over the ENABLE_MOONSHINE_WSI=1 that
          # Moonshine sets on the environment).
          export DISABLE_MOONSHINE_WSI=1
          unset ENABLE_MOONSHINE_WSI

          # No bwrap here: gamescope spawns its own Xwayland, and inside
          # bwrap's user namespace the root-owned /tmp/.X11-unix appears owned
          # by "nobody", which wlroots rejects. Without the sandbox the check
          # passes (the directory is root-owned).
          gs_args=(--steam -f -b -W "$w" -H "$h" -w "$w" -h "$h" -r "$rate" --hdr-enabled)
          exec ${gamescopeHdr}/bin/gamescope "''${gs_args[@]}" -- steam -tenfoot
        '';
      };

      moonshine-heroic = pkgs.writeShellApplication {
        name = "moonshine-heroic";
        runtimeInputs = [ pkgs.heroic ];
        text = ''
          exec heroic --console
        '';
      };
    in
    {
      options.modules.streaming.shellApplications = lib.mkOption {
        type = lib.types.attrsOf lib.types.package;
        default = { };
        description = "Shell applications generated for the streaming service.";
      };

      config = {
        modules.streaming.shellApplications = {
          inherit
            moonshine-desktop
            moonshine-steam
            moonshine-steam-gamescope-hdr
            moonshine-heroic
            ;
        };

        services.moonshine = {
          enable = true;
          inherit user;
          firewallInterfaces = [ "eth0" ];

          settings = {
            name = config.networking.hostName;
            application = [
              {
                title = "Desktop";
                boxart = "${moonshine-boxart}/desktop.png";
                command = [ "${moonshine-desktop}/bin/moonshine-desktop" ];
                stdout = "journal";
                stderr = "journal";
              }
              {
                title = "Steam Big Picture";
                boxart = "${moonshine-boxart}/steam.png";
                command = [ "${moonshine-steam}/bin/moonshine-steam" ];
                stdout = "journal";
                stderr = "journal";
              }
              {
                title = "Steam Big Picture (gamescope HDR)";
                boxart = "${moonshine-boxart}/steam.png";
                command = [ "${moonshine-steam-gamescope-hdr}/bin/moonshine-steam-gamescope-hdr" ];
                stdout = "journal";
                stderr = "journal";
              }
              {
                title = "Heroic Games Launcher";
                boxart = "${moonshine-boxart}/heroic.png";
                command = [ "${moonshine-heroic}/bin/moonshine-heroic" ];
                stdout = "journal";
                stderr = "journal";
              }
            ];
          };
        };
      };
    };
}
