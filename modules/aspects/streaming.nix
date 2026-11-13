{
  den,
  lib,
  ...
}:
let
  stopDesktopSteam = ''
    if pgrep -x steam >/dev/null; then
      steam -shutdown >/dev/null 2>&1 || true
      for _ in $(seq 1 30); do
        pgrep -x steam >/dev/null || break
        sleep 1
      done
    fi
  '';

  moonshineStreaming = ''
    moonshine_streaming() {
      local since last
      systemctl is-active --quiet moonshine || return 1
      since=$(date -d "$(systemctl show moonshine -p ActiveEnterTimestamp --value 2>/dev/null)" +%s 2>/dev/null) || return 1
      last=$(journalctl -u moonshine --no-pager -o short-unix --since "@$since" \
        --grep "session::manager: (Starting session streams|Session stopped (by user|unexpectedly))" -n 1 2>/dev/null |
        awk -v s="$since" '$1 >= s' |
        tail -n 1) || return 1
      [ -n "$last" ] || return 1
      grep -q "Starting session streams" <<<"$last"
    }
  '';
in
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
          '';

          steam-session-select = pkgs.writeShellApplication {
            name = "steamos-session-select";
            runtimeInputs = [ config.programs.steam.package ];
            text = ''
              echo "moonshine: SteamOS session request: $*" >&2
              exec steam -shutdown
            '';
          };

          moonshine-steam-game-session = pkgs.writeShellApplication {
            name = "moonshine-steam-game-session";
            runtimeInputs = [
              steam-session-select
              config.programs.steam.package
            ];
            text = ''
              exec steam -tenfoot
            '';
          };

          # Run Steam through Gamescope so Moonshine always captures one stable HDR
          # surface. Steam's overlay does not composite with gamescope-wsi; that is
          # ValveSoftware/gamescope#1537, still open, and the local PoC that
          # addressed it was dropped. Expect no Steam overlay in this session.
          moonshine-steam = pkgs.writeShellApplication {
            name = "moonshine-steam";
            runtimeInputs = [
              pkgs.gamescope
              pkgs.procps
              config.programs.steam.package
            ];
            text = ''
              ${stopDesktopSteam}

              export XDG_DATA_DIRS="${config.services.moonshine.package}/share:${pkgs.gamescope}/share:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

              w=''${MOONSHINE_CLIENT_WIDTH:-1920}
              h=''${MOONSHINE_CLIENT_HEIGHT:-1080}
              rate=''${MOONSHINE_CLIENT_FRAMERATE:-60}

              # Moonshine's Vulkan WSI layer is installed where the loader scans
              # (the system profile share dir, on XDG_DATA_DIRS), so games pick
              # it up and present their swapchains straight to the Moonshine
              # compositor instead of being captured and colour-converted.
              # Moonshine sets ENABLE_MOONSHINE_WSI=1 itself; DISABLE_* takes
              # precedence over it, so it must stay unset.
              unset DISABLE_MOONSHINE_WSI

              # Steam Overlay only hooks X11 windows, while gamescope-wsi bypasses
              # Xwayland for game swapchains, so the overlay is not expected to
              # appear. See ValveSoftware/gamescope#1537.
              unset DISABLE_GAMESCOPE_WSI

              gs_args=(--steam -f -b -W "$w" -H "$h" -w "$w" -h "$h" -r "$rate" --hdr-enabled)
              # GameMode wraps the compositor so the whole session (gamescope,
              # Steam client and game) keeps the performance governor, the best
              # effort I/O priority and the screensaver inhibit while it runs.
              exec ${config.programs.gamemode.package}/bin/gamemoderun ${pkgs.gamescope}/bin/gamescope "''${gs_args[@]}" -- ${moonshine-steam-game-session}/bin/moonshine-steam-game-session
            '';
          };
          # Moonshine runs this as ExecStopPost on the session's transient unit,
          # whose environment is built by Moonshine itself and does not promise
          # DBUS_SESSION_BUS_ADDRESS. So pin it before starting the user unit:
          # without it systemctl --user silently talks to no bus and the restore
          # never happens.
          steam-restore-trigger = pkgs.writeShellApplication {
            name = "steam-restore-trigger";
            runtimeInputs = [ pkgs.systemd ];
            text = ''
              export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus}"
              exec systemctl --user start steam-tray
            '';
          };

          moonshine-desktop = pkgs.writeShellApplication {
            name = "moonshine-desktop";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.foot
              pkgs.xdg-terminal-exec
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

              home_dir="''${HOME:-/home/${sessionUser}}"
              export XDG_DATA_DIRS="''${home_dir}/.nix-profile/share:/nix/profile/share:''${home_dir}/.local/state/nix/profile/share:/etc/profiles/per-user/${sessionUser}/share:/nix/var/nix/profiles/default/share:/run/current-system/sw/share:''${home_dir}/.local/share:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
              export PATH="''${PATH}:/run/wrappers/bin:''${home_dir}/.nix-profile/bin:/nix/profile/bin:''${home_dir}/.local/state/nix/profile/bin:/etc/profiles/per-user/${sessionUser}/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"

              niri >"$work/niri.log" 2>&1 &
              niri_pid=$!
              tail -n +1 -f "$work/niri.log" &
              tail_pid=$!

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
            nixpkgs.overlays = [
              (_final: prev: {
                gamescope = (prev.gamescope.override { enableWsi = true; }).overrideAttrs (old: {
                  postPatch = (old.postPatch or "") + ''
                    substituteInPlace subprojects/vkroots/vkroots.h --replace-fail \
                      'deviceDispatch->GetDeviceQueue(device, queueInfo.queueFamilyIndex, j, &queue);' \
                      'if (queueInfo.flags) { VkDeviceQueueInfo2 q2; q2.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_INFO_2; q2.pNext = nullptr; q2.flags = queueInfo.flags; q2.queueFamilyIndex = queueInfo.queueFamilyIndex; q2.queueIndex = j; deviceDispatch->GetDeviceQueue2(device, &q2, &queue); } else deviceDispatch->GetDeviceQueue(device, queueInfo.queueFamilyIndex, j, &queue);'

                    substituteInPlace subprojects/vkroots/vkroots.h --replace-fail \
                      'deviceDispatch->GetDeviceQueue(device, queueInfo.queueFamilyIndex, i, &queue);' \
                      'if (queueInfo.flags) { VkDeviceQueueInfo2 q2; q2.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_INFO_2; q2.pNext = nullptr; q2.flags = queueInfo.flags; q2.queueFamilyIndex = queueInfo.queueFamilyIndex; q2.queueIndex = i; deviceDispatch->GetDeviceQueue2(device, &q2, &queue); } else deviceDispatch->GetDeviceQueue(device, queueInfo.queueFamilyIndex, i, &queue);'
                  '';
                });
              })
            ];

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
                    post_command = [ [ "${steam-restore-trigger}/bin/steam-restore-trigger" ] ];
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
          pkgs.coreutils
          pkgs.evtest
          pkgs.gawk
          pkgs.jq
          pkgs.niri
          pkgs.openssh
          pkgs.procps
          pkgs.systemd
          osConfig.programs.steam.package
        ];
        text = ''
          ssh_tv() {
            ssh -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR -o RequestTTY=force tv "$@"
          }

          start_ts=$(date +%s.%N)
          log() {
            awk -v a="$start_ts" -v b="$(date +%s.%N)" -v m="$*" \
              'BEGIN { printf "[%7.3fs] %s\n", b - a, m }' >&2
          }

          joystick_node() {
            local node event
            for node in /dev/input/by-id/*event-joystick; do
              [ -e "$node" ] || continue
              event="$(basename "$(readlink -f "$node")")"
              if [ "$(cat "/sys/class/input/$event/device/id/vendor" 2>/dev/null)" = 2dc8 ] &&
                [ "$(cat "/sys/class/input/$event/device/id/product" 2>/dev/null)" = 310a ]; then
                printf '%s\n' "$node"
                return 0
              fi
            done
            return 1
          }

          wait_button() {
            local node deadline
            deadline=$((SECONDS + $1))
            while :; do
              node="$(joystick_node)" && break
              [ "$SECONDS" -lt "$deadline" ] || { log "no 2dc8:310a joystick node appeared"; return 1; }
              sleep 0.2
            done
            log "joystick node resolved: $node"
            local status=1 event_fd reader line remaining
            local press='type 1 \(EV_KEY\), code [0-9]+ \([^)]*\), value 1$'
            remaining=$((deadline - SECONDS))
            [ "$remaining" -gt 0 ] || return 1
            # Stop the reader explicitly: exiting grep does not unblock evtest's
            # next device read, and Bash waits for every process in a pipeline.
            exec {event_fd}< <(exec timeout "$remaining" stdbuf -oL evtest "$node" 2>&1)
            reader=$!
            while IFS= read -r -u "$event_fd" line; do
              if [[ "$line" =~ $press ]]; then
                status=0
                break
              fi
            done
            kill "$reader" 2>/dev/null || true
            wait "$reader" 2>/dev/null || true
            exec {event_fd}<&-
            if [ "$status" = 0 ]; then
              log "button press seen"
            else
              log "no button press within ''${1}s"
            fi
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

          wait_button 30 || { log "no press; exiting without action"; exit 0; }

          ${moonshineStreaming}

          if moonshine_streaming; then
            log "live stream detected; leaving the session alone"
            exit 0
          fi

          tv_on=0
          if power="$(ssh_tv 'luna-send -n 1 -w 3000 -f luna://com.webos.service.tvpower/power/getPowerState "{}"' 2>/dev/null)"; then
            if jq -e '.state == "Active"' >/dev/null <<<"$power"; then
              tv_on=1
            fi
          fi
          log "tv power: $([ "$tv_on" -eq 1 ] && echo on || echo off)"

          if [ "$tv_on" -eq 1 ]; then
            # webOS only delivers launch params on a cold start: a lingering
            # Moonlight is re-foregrounded via webOSRelaunch with params
            # dropped, landing on the app picker instead of Steam. Close first
            # (a failed close just means it was not running), then launch.
            log "branch: tv (cold-launch Moonlight)"
            ssh_tv ${lib.escapeShellArg closeRemote} >/dev/null 2>&1 || true
            sleep 1
            ssh_tv ${lib.escapeShellArg launchRemote} >/dev/null
            log "branch: tv done"
            exit 0
          fi

          session_unlocked || { log "no unlocked seat session; exiting"; exit 0; }
          [ -n "''${WAYLAND_DISPLAY:-}" ] || { log "no wayland display; exiting"; exit 0; }

          # Already on the desk inside a Steam game: the button press is input
          # to that game, not a request to relaunch anything. Steam spawns a
          # `reaper SteamLaunch AppId=...` child for a running (or launching)
          # game; plain Big Picture has none, and still gets focus + raise.
          if pgrep -f "reaper SteamLaunch" >/dev/null; then
            log "steam game already running on the desk; leaving it alone"
            exit 0
          fi

          log "branch: desk"


          niri msg action focus-monitor DP-1 >/dev/null

          if pgrep -x gamescope >/dev/null; then
            log "reusing the running gamescope session"
            exec ${lib.getExe osConfig.programs.steam.package} -tenfoot -pipewire-dmabuf
          fi

          log "taking over: stopping desktop steam, starting gamescope"
          ${stopDesktopSteam}

          ${osConfig.programs.gamemode.package}/bin/gamemoderun ${lib.getExe pkgs.gamescope} --steam -H 1080 -r 162 --adaptive-sync -- \
            ${lib.getExe osConfig.programs.steam.package} -tenfoot -pipewire-dmabuf || true

          log "session ended; restoring desktop steam"
          systemctl --user start steam-tray
        '';
      };

      steam-tray-launch = pkgs.writeShellApplication {
        name = "steam-tray-launch";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gawk
          pkgs.procps
          pkgs.systemd
          osConfig.programs.steam.package
        ];
        text = ''
          log() {
            printf 'steam-tray: %s\n' "$*" >&2
          }

          ${moonshineStreaming}

          sleep 10

          if moonshine_streaming; then
            log "a session is live; leaving desktop steam alone"
            exit 0
          fi
          if pgrep -x steam >/dev/null; then
            log "desktop steam already running; nothing to restore"
            exit 0
          fi
          log "restoring desktop steam"
          exec ${lib.getExe osConfig.programs.steam.package} -silent
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

      systemd.user.services.steam-tray = {
        Unit = {
          Description = "Desktop Steam (tray)";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          Type = "simple";
          ExecStart = lib.getExe steam-tray-launch;
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    };
}
