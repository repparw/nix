{
  lib,
  ...
}:
{
  den.aspects.streaming = {
    nixos =
      { config, pkgs, ... }:
      let
        cfg = config.modules.streaming;

        loadNiriEnv = ''
          while IFS= read -r line; do
            export "$line"
          done < <(
            systemctl --user show-environment | ${lib.getExe pkgs.ripgrep} '^(DISPLAY|NIRI_SOCKET|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|XDG_SESSION_TYPE)='
          )
        '';

        outputOnScript = pkgs.writeShellScriptBin "stream-output-on" ''
          set -eu

          ${loadNiriEnv}

          ${lib.getExe pkgs.niri} msg output ${cfg.output} on
          ${lib.getExe pkgs.niri} msg output ${cfg.output} mode ${cfg.width}x${cfg.height}@${cfg.refreshRate}
          ${lib.getExe pkgs.niri} msg output ${cfg.output} position set ${toString cfg.positionX} ${toString cfg.positionY}
          ${lib.getExe pkgs.niri} msg output ${cfg.output} vrr on --on-demand
        '';

        outputOffScript = pkgs.writeShellScriptBin "stream-output-off" ''
          set -eu

          ${loadNiriEnv}

          ${lib.getExe pkgs.niri} msg output ${cfg.output} off
        '';

        gamescopeSessionScript = pkgs.writeShellScriptBin "gamescope-stream-session" ''
          set -eu

          exec >"/tmp/gamescope-stream-session.log" 2>&1
          set -x

          ${loadNiriEnv}
          ${outputOnScript}/bin/stream-output-on

          ${lib.getExe pkgs.niri} msg action focus-monitor ${cfg.output} || true

          cleanup() {
            ${lib.getExe pkgs.niri} msg action focus-monitor ${cfg.desktopOutput} || true
          }

          trap cleanup EXIT INT TERM

          export DXVK_HDR=1
          export ENABLE_GAMESCOPE_WSI=1
          export STEAM_GAMESCOPE_HDR_SUPPORTED=1

          ${lib.getExe pkgs.gamescope} \
            --backend wayland \
            --fullscreen \
            --borderless \
            --steam \
            --force-windows-fullscreen \
            -W ${cfg.width} \
            -H ${cfg.height} \
            -w ${cfg.width} \
            -h ${cfg.height} \
            -r ${cfg.refreshRate} \
            --adaptive-sync${lib.optionalString cfg.hdr " --hdr-enabled"} \
            -- ${lib.getExe pkgs.steam} -tenfoot -pipewire-dmabuf &
          gamescope_pid=$!

          ${lib.getExe' pkgs.coreutils "sleep"} 2
          ${lib.getExe pkgs.niri} msg action focus-monitor ${cfg.desktopOutput} || true

          wait "$gamescope_pid"
        '';

        remoteStartScript = pkgs.writeShellScriptBin "stream-session-start" ''
          set -eu

          systemctl --machine=repparw@.host --user start sunshine.service

          if systemctl --machine=repparw@.host --user restart gamescope-stream-session.service; then
            exec systemctl --machine=repparw@.host --user status gamescope-stream-session.service
          fi

          systemctl --machine=repparw@.host --user status gamescope-stream-session.service || true
          echo
          echo "--- /tmp/gamescope-stream-session.log ---"
          tail -n 200 /tmp/gamescope-stream-session.log || true
          exit 1
        '';

        remoteStopScript = pkgs.writeShellScriptBin "stream-session-stop" ''
          set -eu
          exec systemctl --machine=repparw@.host --user stop gamescope-stream-session.service
        '';

        remoteStatusScript = pkgs.writeShellScriptBin "stream-session-status" ''
          set -eu
          exec systemctl --machine=repparw@.host --user status gamescope-stream-session.service
        '';

        localRunScript = pkgs.writeShellScriptBin "stream-session-run-user" ''
          set -eu

          cleanup() {
            systemctl --user stop gamescope-stream-session.service >/dev/null 2>&1 || true
          }

          trap cleanup EXIT INT TERM

          systemctl --user restart gamescope-stream-session.service

          while systemctl --user is-active --quiet gamescope-stream-session.service; do
            ${lib.getExe' pkgs.coreutils "sleep"} 2
          done
        '';

        sunshineApps = {
          env = {
            PATH = "$(PATH):/run/current-system/sw/bin";
          };
          apps = [
            {
              name = "Desktop";
            }
            {
              name = "Steam Big Picture (DP-2)";
              cmd = "${localRunScript}/bin/stream-session-run-user";
            }
          ];
        };
      in
      {
        options.modules.streaming = {
          output = lib.mkOption {
            type = lib.types.str;
            default = "DP-2";
            description = "Output used for the dedicated streaming workspace";
          };

          desktopOutput = lib.mkOption {
            type = lib.types.str;
            default = "DP-1";
            description = "Desktop output to refocus after launching the streaming session";
          };

          width = lib.mkOption {
            type = lib.types.str;
            default = "3840";
            description = "Streaming width";
          };

          height = lib.mkOption {
            type = lib.types.str;
            default = "2160";
            description = "Streaming height";
          };

          refreshRate = lib.mkOption {
            type = lib.types.str;
            default = "120";
            description = "Streaming refresh rate";
          };

          positionX = lib.mkOption {
            type = lib.types.int;
            default = 10000;
            description = "X position for the virtual streaming output inside Niri";
          };

          positionY = lib.mkOption {
            type = lib.types.int;
            default = 10000;
            description = "Y position for the virtual streaming output inside Niri";
          };

          hdr = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable HDR flags for the nested gamescope session";
          };

          sunshineOutput = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = 2;
            description = "Sunshine output index for the dedicated streaming output";
          };
        };

        config = {
          services.sunshine = {
            enable = true;
            autoStart = true;
            openFirewall = true;
            capSysAdmin = true;
            applications = sunshineApps;
            settings = lib.optionalAttrs (cfg.sunshineOutput != null) {
              output_name = cfg.sunshineOutput;
            };
          };

          environment.systemPackages = [
            remoteStartScript
            remoteStatusScript
            remoteStopScript
          ];

          systemd.user.services.gamescope-stream-session = {
            description = "Dedicated nested gamescope stream session";
            after = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];

            serviceConfig = {
              ExecStart = "${gamescopeSessionScript}/bin/gamescope-stream-session";
              ExecStopPost = "${outputOffScript}/bin/stream-output-off";
              Restart = "on-failure";
              RestartSec = "2s";
            };
          };
        };
      };
  };
}
