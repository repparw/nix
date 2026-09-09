{
  den,
  lib,
  ...
}:
{
  den.aspects.streaming.provides.to-hosts =
    { user, ... }:
    {
      nixos =
        {
          config,
          pkgs,
          ...
        }:
        let
          sessionUser = user.name;

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

          # Steam is single-instance per user; stop the desktop instance so it
          # cannot steal Big Picture from Moonshine's private compositor.
          stopDesktopSteam = ''
            if pgrep -x steam >/dev/null; then
              steam -shutdown >/dev/null 2>&1 || true
              for _ in $(seq 1 30); do
                pgrep -x steam >/dev/null || break
                sleep 1
              done
            fi
          '';

          # HDR needs gamescope's own WSI layer so clients can present HDR surfaces
          # to gamescope; nixpkgs disables it by default.
          gamescopeHdr = (pkgs.gamescope.override { enableWsi = true; }).overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./gamescope-wsi-overlay.patch ];
          });

          # Run Steam through Gamescope so Moonshine always captures one stable HDR
          # surface. Steam's overlay does not normally composite with gamescope-wsi;
          # the local patch opts into the proof of concept from
          # ValveSoftware/gamescope#1537.
          moonshine-steam-hdr = pkgs.writeShellApplication {
            name = "moonshine-steam-hdr";
            runtimeInputs = [
              gamescopeHdr
              pkgs.bubblewrap
              pkgs.procps
              # Use the NixOS-configured wrapper so extraCompatPackages (GE-Proton)
              # is exported to Steam inside Moonshine's transient session too.
              config.programs.steam.package
            ];
            text = ''
              ${stopDesktopSteam}

              # Gamescope's WSI layer must remain discoverable for the HDR entry.
              # moonshine-wsi is force-disabled below.
              export XDG_DATA_DIRS="${config.services.moonshine.package}/share:${gamescopeHdr}/share:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

              # Workaround for hgaiser/moonshine#93 (HDR/DX11 black screen):
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

              # Steam Overlay only hooks X11 windows, while gamescope-wsi bypasses
              # Xwayland for game swapchains. Opt into the upstream PoC from
              # ValveSoftware/gamescope#1537.
              unset DISABLE_GAMESCOPE_WSI
              export GAMESCOPE_WSI_FIX_OVERLAY=1

              # bwrap sits INSIDE gamescope, not outside: gamescope spawns its own
              # Xwayland, and inside bwrap's user namespace the root-owned
              # /tmp/.X11-unix appears owned by "nobody", which wlroots rejects
              # (segfault). Here gamescope sets up Xwayland outside the sandbox
              # and only the Steam child is sandboxed. The sandbox masks the
              # Seagate automounts: Steam stats every mount at startup (drive
              # enumeration) and Proton maps them as DOS drives (verified with
              # strace 2026-09-05), which would otherwise spin up the idle disk
              # on every launch. Overlay diagnostic 2026-09-06: removing this
              # sandbox did not restore the overlay, so the sandbox is exonerated.
              gs_args=(--steam -f -b -W "$w" -H "$h" -w "$w" -h "$h" -r "$rate" --hdr-enabled)
              exec ${gamescopeHdr}/bin/gamescope "''${gs_args[@]}" -- bwrap \
                --dev-bind / / \
                --tmpfs /mnt/seagate \
                --tmpfs /home/containers/media/seagate \
                -- steam -tenfoot
            '';
          };
        in
        {
          config = {
            services.moonshine = {
              enable = true;
              user = sessionUser;
              firewallInterfaces = [ "eth0" ];

              settings = {
                name = config.networking.hostName;

                # Grace period after the client's last ping before the session is
                # torn down (default 60). A reconnecting client resumes the live
                # session inside this window instead of killing the game; the
                # 19:51:06 drop gave the client only ~44s to come back.
                stream.timeout = 300;
                application = [
                  {
                    # Nested, isolated Niri desktop on Moonshine's Wayland output;
                    # no --session: this is not the user's primary compositor.
                    title = "Desktop";
                    boxart = "${moonshine-boxart}/desktop.png";
                    command = [ (lib.getExe pkgs.niri) ];
                    stdout = "journal";
                    stderr = "journal";
                  }
                  {
                    title = "Steam Big Picture HDR";
                    boxart = "${moonshine-boxart}/steam.png";
                    command = [ "${moonshine-steam-hdr}/bin/moonshine-steam-hdr" ];
                    stdout = "journal";
                    stderr = "journal";
                  }
                  {
                    title = "Heroic Games Launcher";
                    boxart = "${moonshine-boxart}/heroic.png";
                    command = [
                      (lib.getExe pkgs.heroic)
                      "--console"
                    ];
                    stdout = "journal";
                    stderr = "journal";
                  }
                ];
              };
            };

            # Boot race: moonshine's healthcheck starts before the GPU finishes
            # initializing (Vulkan FAIL, exit 1, recovered only by Restart=).
            # Order after udev-settle so DRM probe and firmware load are done
            # before the first healthcheck. (Not After=graphical.target: moonshine
            # is WantedBy multi-user, so that ordering cycles
            # multi-user -> moonshine -> graphical -> multi-user and breaks
            # graphical.target entirely.)
            systemd.services.moonshine.wants = [ "systemd-udev-settle.service" ];
            systemd.services.moonshine.after = [ "systemd-udev-settle.service" ];
          };
        };
    };
}
