{
  den,
  lib,
  ...
}:
let
  # Steam is single-instance per user; stop the desktop instance so it cannot
  # steal Big Picture from a private compositor. Both the Moonshine stream and
  # the controller-driven desk launch need gamescope to own the session, so both
  # go through this.
  stopDesktopSteam = ''
    if pgrep -x steam >/dev/null; then
      steam -shutdown >/dev/null 2>&1 || true
      for _ in $(seq 1 30); do
        pgrep -x steam >/dev/null || break
        sleep 1
      done
    fi
  '';

  # Whether a Moonshine stream is live right now. Shared by the 8bitdo
  # launcher, which must not take over the desk mid-session, and by the
  # restore watcher, which must not revive the tray under a fresh session.
  #
  # The journal alone cannot be trusted: a crashed or killed daemon leaves a
  # stale "Starting session streams" with no matching "stopped" line behind,
  # which would report a phantom stream forever. So require the daemon to be
  # running and only consider session lines at or after its start. Within
  # those, the state machine is exact: the latest terminal line is either
  # streams starting (active) or stopped+waiting (idle). No lines at all
  # fails open.
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
            rsvg-convert \
              --width 512 \
              --height 512 \
              ${pkgs.heroic}/share/icons/hicolor/scalable/apps/com.heroicgameslauncher.hgl.svg \
              > $out/heroic.png
          '';

          # Hidden automatic logging never starts in MangoHud 0.8.4 because it
          # skips the update that starts the logger. flightlessmango/MangoHud#1782.
          withHiddenLogging =
            package:
            package.overrideAttrs (old: {
              postPatch = (old.postPatch or "") + ''
                substituteInPlace src/overlay.cpp --replace-fail \
                  'if (!get_params()->no_display || logger->is_active())' \
                  'if (!get_params()->no_display || logger->is_active() || (get_params()->autostart_log && !logger->autostart_init))'
              '';
            });
          mangohudLogging = withHiddenLogging (
            pkgs.mangohud.override {
              pkgsi686Linux = pkgs.pkgsi686Linux // {
                mangohud = withHiddenLogging pkgs.pkgsi686Linux.mangohud;
              };
            }
          );
          moonshine-steam-game-session = pkgs.writeShellApplication {
            name = "moonshine-steam-game-session";
            runtimeInputs = [
              mangohudLogging
              pkgs.coreutils
              pkgs.findutils
              config.programs.steam.package
            ];
            text = ''
              log_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/moonshine/frame-times"
              mkdir -p "$log_dir"
              find "$log_dir" -maxdepth 1 -type f -name '*.csv' -mtime +7 -delete
              total_bytes=$(du -sb "$log_dir" | cut -f1)
              while IFS= read -r -d $'\0' entry; do
                (( total_bytes > 268435456 )) || break
                read -r _mtime bytes path <<< "$entry"
                rm -- "$path"
                total_bytes=$((total_bytes - bytes))
              done < <(find "$log_dir" -maxdepth 1 -type f -name '*.csv' -printf '%T@ %s %p\0' | sort -zn)
              export MANGOHUD_CONFIG="preset=0,no_display,autostart_log=1,log_duration=0,log_interval=0,output_folder=$log_dir,blacklist=steam+steamwebhelper+heroic"
              exec mangohud steam -tenfoot
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

              # Disk masking lives in the steam package (gaming.nix), so no sandbox here.
              gs_args=(--steam -f -b -W "$w" -H "$h" -w "$w" -h "$h" -r "$rate" --hdr-enabled)
              exec ${pkgs.gamescope}/bin/gamescope "''${gs_args[@]}" -- ${moonshine-steam-game-session}/bin/moonshine-steam-game-session
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
            # Share HDR and the vkroots queue fix with every Gamescope launch.
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

            programs.steam.extraPackages = [ mangohudLogging ];

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
                    # moonshine-steam runs stopDesktopSteam, so the tray client
                    # it kills has to come back when the session ends. Moonshine
                    # runs post_command as ExecStopPost on the session's own
                    # transient unit, so it covers every teardown - a client
                    # disconnect and an app exit alike - and needs no process
                    # left running to watch for it.
                    post_command = [ [ "${steam-restore-trigger}/bin/steam-restore-trigger" ] ];
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

          # Journal every phase with a millisecond offset. Without this the run
          # is a single silent systemd start/stop pair, so a missed press, an
          # unresolved node and a slow TV launch are indistinguishable.
          start_ts=$(date +%s.%N)
          log() {
            awk -v a="$start_ts" -v b="$(date +%s.%N)" -v m="$*" \
              'BEGIN { printf "[%7.3fs] %s\n", b - a, m }' >&2
          }

          # The 2.4GHz dongle re-enumerates as 2dc8:310a whenever the controller
          # powers on, including from a wall charger, so enumeration alone cannot
          # tell charging from playing. xpad maps 0x310a as a plain Xbox 360 pad
          # and reports no battery state, so the only distinguishing signal is
          # real button input.
          #
          # Match on the USB ids, not the product name: the same controller
          # enumerates as "8BitDo IDLE" while powered down and only as "8BitDo
          # Ultimate 2C Wireless Controller" when active, so a name glob misses
          # it and wait_button then times out silently. by-id survives
          # re-enumeration and the -event-joystick suffix keeps the sibling
          # keyboard and mouse nodes out of the way.
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

          # Never interrupt a live session. On controller reconnect the dongle
          # re-enumerates, which alone starts this service, and the power-on
          # press clears the button gate while the user is mid-game and their
          # input is already flowing to that game. So this has to run before
          # every branch: a close+relaunch in the TV branch restarts the video
          # stream even when Moonshine keeps the compositor and app up, which
          # is a visible blip in a session nobody asked to touch.
          #
          # Recovering a genuinely wedged stream is then two steps - quit the
          # app on the TV, or wait out stream.timeout, and the next press
          # works. That trade was deliberate: the old TV-first ordering could
          # only ever restart the stream, never the wedged app, and it cost a
          # blink on every controller return from out of range.
          #
          # Checked after the press rather than before it, so the arming window
          # stays useful: a session that ends before the press still gets the
          # launch it would have had.
          wait_button 30 || { log "no press; exiting without action"; exit 0; }

          ${moonshineStreaming}

          if moonshine_streaming; then
            log "live stream detected; leaving the session alone"
            exit 0
          fi

          # First path: the TV wins whenever it is on. A session cannot be live
          # by this point, so a relaunch is a request for one rather than an
          # interruption, and the desk-session gating below never gets a chance
          # to matter while the TV is up.
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

          # Big Picture always runs under gamescope here, so HDR, 1080p162 and
          # adaptive sync apply the same way they do for a stream. An existing
          # gamescope session (plain BP, no game) is reused as-is; anything
          # else means taking over, so stop the desktop Steam client first.
          # Without this, single-instance Steam would just switch itself to BP
          # outside the new compositor and leave gamescope empty. The guards
          # above already ruled out a live stream and a running game, so the
          # only casualty here is a tray/downloading client, which resumes.
          if pgrep -x gamescope >/dev/null; then
            log "reusing the running gamescope session"
            exec ${lib.getExe osConfig.programs.steam.package} -tenfoot -pipewire-dmabuf
          fi

          log "taking over: stopping desktop steam, starting gamescope"
          ${stopDesktopSteam}

          # Foreground, not exec: the tail below has to run once the session
          # ends, and exec would replace this script with gamescope.
          ${lib.getExe pkgs.gamescope} --steam -H 1080 -r 162 --adaptive-sync -- \
            ${lib.getExe osConfig.programs.steam.package} -tenfoot -pipewire-dmabuf || true

          # Revive the tray client through its own unit. Doing it here would
          # keep this service active forever - the udev rule re-triggers it on
          # every controller re-enumeration and a start on an already active
          # unit is a no-op, so the button would go dead - and would place the
          # client in this service's cgroup, where the next stop kills it.
          log "session ended; restoring desktop steam"
          systemctl --user start steam-tray
        '';
      };

      # Guarded launcher for the tray client. Moonshine's post_command starts
      # this unit when a session ends, so the hold has to live here rather than
      # there: it must not block the transient session unit's stop job, but it
      # does have to outlast a relaunch before deciding.
      #
      # A relaunch from the TV, or a button press with the TV on, produces a
      # session stop immediately followed by a session start. Restoring in that
      # window would only have the next session's stopDesktopSteam kill it
      # again and stall that session for as long as steam takes to shut down.
      # Ten seconds is longer than the TV close+relaunch gap, so a relaunch has
      # logged "Starting session streams" by the time this runs, and the guard
      # simply leaves the unit inactive.
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

      # On-demand tray client, deliberately not WantedBy anything: it exists to
      # revive the desktop Steam that a session shut down, so it is started by
      # Moonshine's post_command or by the launcher above rather than at login.
      # A separate unit because restoring it inline would pin the caller active
      # and, in the launcher's case, put the client in its cgroup. No Restart=,
      # so quitting the tray stays honoured; a crash is recovered by the next
      # session end.
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
      };
    };
}
