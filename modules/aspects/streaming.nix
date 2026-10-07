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
          gamescopeHdr = pkgs.gamescope.override { enableWsi = true; };

          # Run Steam through Gamescope so Moonshine always captures one stable HDR
          # surface. Steam's overlay does not composite with gamescope-wsi; that is
          # ValveSoftware/gamescope#1537, still open, and the local PoC that
          # addressed it was dropped. Expect no Steam overlay in this session.
          moonshine-steam = pkgs.writeShellApplication {
            name = "moonshine-steam";
            runtimeInputs = [
              gamescopeHdr
              pkgs.bubblewrap
              pkgs.procps
              config.programs.steam.package
            ];
            text = ''
              ${stopDesktopSteam}

              export XDG_DATA_DIRS="${config.services.moonshine.package}/share:${gamescopeHdr}/share:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

              # Workaround for hgaiser/moonshine#93 (HDR/DX11 black screen):
              # wrap Steam in Gamescope at the client's resolution. Gamescope owns
              # the surface Moonshine's compositor sees, so games present to
              # Gamescope instead of creating their own (HDR 1x1) WSI swapchain.
              w=''${MOONSHINE_CLIENT_WIDTH:-1920}
              h=''${MOONSHINE_CLIENT_HEIGHT:-1080}
              rate=''${MOONSHINE_CLIENT_FRAMERATE:-60}

              # Moonshine's Vulkan WSI layer is installed where the loader scans
              # (the system profile share dir, on XDG_DATA_DIRS), so games pick
              # it up and present their swapchains straight to the Moonshine
              # compositor instead of being captured and colour-converted. The
              # layer used to be disabled here on the belief that it breaks
              # gamescope, but gamescope presents to Moonshine as a Wayland
              # client either way, and nothing had ever confirmed the layer was
              # even loading. Enabling it is what makes that testable.
              # Moonshine sets ENABLE_MOONSHINE_WSI=1 itself; DISABLE_* takes
              # precedence over it, so it must stay unset.
              unset DISABLE_MOONSHINE_WSI

              # Steam Overlay only hooks X11 windows, while gamescope-wsi bypasses
              # Xwayland for game swapchains, so the overlay is not expected to
              # appear. See ValveSoftware/gamescope#1537.
              unset DISABLE_GAMESCOPE_WSI

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
          # Desktop stream: nested niri plus a kiosk launcher loop. Vicinae
          # cannot serve the stream (its daemon is bound to the login
          # session's display), so fuzzel -- a plain Wayland client --
          # opens whenever the nested compositor has no windows. It is already
          # focused when it appears, so typing filters immediately with no
          # Mod key and no lost first character. Phone-friendly by design.
          moonshine-desktop = pkgs.writeShellApplication {
            name = "moonshine-desktop";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.foot
              pkgs.fuzzel
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
              pkgs.niri
            ];
            text = ''
              work="$(mktemp -d)"
              niri_pid=""
              tail_pid=""
              cleanup() {
                if [ -n "$tail_pid" ]; then kill "$tail_pid" 2>/dev/null || true; fi
                if [ -n "$niri_pid" ]; then kill "$niri_pid" 2>/dev/null || true; fi
                rm -rf "$work"
              }
              trap cleanup EXIT

              # Moonshine launches with systemd's default environment; fuzzel
              # needs the system application database to list anything.
              home_dir="''${HOME:-/home/${sessionUser}}"
              export XDG_DATA_DIRS="/run/current-system/sw/share:''${home_dir}/.nix-profile/share:''${home_dir}/.local/share:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

              niri >"$work/niri.log" 2>&1 &
              niri_pid=$!
              tail -n +1 -f "$work/niri.log" &
              tail_pid=$!

              # niri prints its exact IPC socket on startup; capture it
              # instead of guessing, then derive the Wayland display from it.
              sock=""
              for _ in $(seq 1 200); do
                sock="$(grep -Eo '/run/user/[0-9]+/niri\.wayland-[^[:space:]"]+\.sock' "$work/niri.log" 2>/dev/null | head -n 1 || true)"
                if [ -n "$sock" ] && [ -S "$sock" ]; then break; fi
                sock=""
                if ! kill -0 "$niri_pid" 2>/dev/null; then break; fi
                sleep 0.1
              done
              if [ -z "$sock" ]; then
                echo "moonshine-desktop: nested niri published no IPC socket" >&2
                exit 1
              fi
              display="$(basename "$sock" | sed -E 's/^niri\.(wayland-[0-9]+)\.[0-9]+\.sock$/\1/')"
              export NIRI_SOCKET="$sock"
              export WAYLAND_DISPLAY="$display"
              echo "moonshine-desktop: nested niri on $WAYLAND_DISPLAY ($NIRI_SOCKET)" >&2

              while kill -0 "$niri_pid" 2>/dev/null; do
                windows="$(niri msg --json windows 2>/dev/null | jq -r 'length' 2>/dev/null || echo '?')"
                if [ "$windows" = "0" ]; then
                  fuzzel || true
                  sleep 1
                else
                  sleep 2
                fi
              done
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

                stream.timeout = 300;
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

            services.udev.extraRules = ''
              ACTION=="add", SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_JOYSTICK}=="1", ATTRS{idVendor}=="2dc8", ATTRS{idProduct}=="310a", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}+="8bitdo-tv-moonlight.service"
            '';
          };
        };
    };

  den.aspects.streaming.homeManager =
    { osConfig, pkgs, ... }:
    let
      moonlightAppId = "com.limelight.webos";
      moonshineHostUuid = "dd0f9f90-97b2-4959-84fe-c4676ffce110";
      steamAppId = 594305089;
      launchPayload = builtins.toJSON {
        id = moonlightAppId;
        params = {
          host_uuid = moonshineHostUuid;
          host_app_id = steamAppId;
        };
      };
      launchRemote = "luna-send -n 1 -w 3000 -f luna://com.webos.applicationManager/launch '${launchPayload}'";
      closeRemote = "luna-send -n 1 -f luna://com.webos.service.applicationmanager/closeByAppId '{\"id\":\"${moonlightAppId}\"}'";
      launch = pkgs.writeShellApplication {
        name = "8bitdo-tv-moonlight";
        runtimeInputs = [
          pkgs.evtest
          pkgs.jq
          pkgs.niri
          pkgs.openssh
          pkgs.procps
          pkgs.systemd
        ];
        text = ''
          ssh_tv() {
            ssh -o BatchMode=yes -o ConnectTimeout=5 -o RequestTTY=force tv "$@"
          }

          # The 2.4GHz dongle re-enumerates as 2dc8:310a whenever the controller
          # powers on, including from a wall charger, so enumeration alone cannot
          # tell charging from playing. xpad maps 0x310a as a plain Xbox 360 pad
          # and reports no battery state, so the only distinguishing signal is
          # real button input. by-id survives re-enumeration and the
          # -event-joystick suffix keeps the sibling keyboard and mouse nodes
          # out of the way.
          joystick_node() {
            local node
            for node in /dev/input/by-id/*Ultimate_2C*event-joystick; do
              [ -e "$node" ] || continue
              printf '%s\n' "$node"
              return 0
            done
            return 1
          }

          wait_button() {
            local node deadline
            deadline=$((SECONDS + $1))
            while :; do
              node="$(joystick_node)" && break
              [ "$SECONDS" -lt "$deadline" ] || return 1
              sleep 0.2
            done
            # grep -m1 closes the pipe on the first button press, which kills
            # evtest with SIGPIPE; pipefail would turn that into a failed gate.
            local status
            set +o pipefail
            timeout "$1" evtest "$node" 2>&1 |
              grep -qm1 -E 'type 1 \(EV_KEY\), code [0-9]+ \([^)]*\), value 1'
            status=$?
            set -o pipefail
            return "$status"
          }

          session_unlocked() {
            local session _uid user class seat hint
            while read -r session _uid user _; do
              [ "$user" = "$USER" ] || continue
              class="$(loginctl show-session "$session" -p Class --value 2>/dev/null || true)"
              seat="$(loginctl show-session "$session" -p Seat --value 2>/dev/null || true)"
              hint="$(loginctl show-session "$session" -p LockedHint --value 2>/dev/null || true)"
              if [ "$class" = user ] && [ -n "$seat" ] && [ "$hint" = no ]; then
                return 0
              fi
            done < <(loginctl list-sessions --no-legend)
            return 1
          }

          wait_button 30 || exit 0

          # Never interrupt a live stream: on controller reconnect the dongle
          # re-enumerates and the button gate above passes (the user is mashing
          # buttons), but their input is already flowing to the game. This is
          # checked before any branch, because both the TV relaunch and the
          # desk focus/launch would tear down an in-progress session. The
          # journal session state machine is precise: the latest terminal
          # line is either streams starting (active) or stopped+waiting (idle).
          # No lines (never streamed since boot) fails open to launching.
          moonshine_streaming() {
            journalctl -u moonshine --no-pager -n 1000 2>/dev/null |
              grep -E "session::manager: (Starting session streams|Session stopped (by user|unexpectedly))" |
              tail -n 1 |
              grep -q "Starting session streams"
          }

          moonshine_streaming && exit 0

          tv_on=0
          if power="$(ssh_tv 'luna-send -n 1 -w 3000 -f luna://com.webos.service.tvpower/power/getPowerState "{}"' 2>/dev/null)"; then
            if jq -e '.state == "Active"' >/dev/null <<<"$power"; then
              tv_on=1
            fi
          fi

          if [ "$tv_on" -eq 1 ]; then
            # webOS only delivers launch params on a cold start: a lingering
            # Moonlight is re-foregrounded via webOSRelaunch with params
            # dropped, landing on the app picker instead of Steam. Close first
            # (a failed close just means it was not running), then launch.
            ssh_tv ${lib.escapeShellArg closeRemote} >/dev/null 2>&1 || true
            sleep 1
            ssh_tv ${lib.escapeShellArg launchRemote} >/dev/null
            exit 0
          fi

          session_unlocked || exit 0
          [ -n "''${WAYLAND_DISPLAY:-}" ] || exit 0

          # Already on the desk inside a Steam game: the button press is input
          # to that game, not a request to relaunch anything. Steam spawns a
          # `reaper SteamLaunch AppId=...` child for a running (or launching)
          # game; plain Big Picture has none, and still gets focus + raise.
          if pgrep -f "reaper SteamLaunch" >/dev/null; then
            exit 0
          fi

          niri msg action focus-monitor DP-1 >/dev/null

          if pgrep -x gamescope >/dev/null || pgrep -x steam >/dev/null; then
            exec ${lib.getExe osConfig.programs.steam.package} -tenfoot -pipewire-dmabuf
          fi

          exec ${lib.getExe pkgs.gamescope} --steam -H 1080 -r 162 --adaptive-sync -- \
            ${lib.getExe osConfig.programs.steam.package} -tenfoot -pipewire-dmabuf
        '';
      };
    in
    {
      home.packages = [ launch ];

      systemd.user.services."8bitdo-tv-moonlight" = {
        Unit = {
          Description = "Start Steam via TV Moonlight or local Big Picture when the 8BitDo connects and a button is pressed";
          After = [
            "network-online.target"
            "graphical-session.target"
          ];
        };
        Service = {
          Type = "exec";
          ExecStart = lib.getExe launch;
        };
      };
    };
}
