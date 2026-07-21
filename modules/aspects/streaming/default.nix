{
  lib,
  config,
  pkgs,
  ...
}:

# TODO: HDR over Sunshine is currently blocked by multiple missing pieces:
#   1. Niri doesn't support HDR output even with an HDR EDID.
#   2. capSysAdmin = false forces wlroots screencopy capture instead of KMS;
#      HDR on Linux generally needs KMS.
#   3. Dummy/virtual DRM driver lacks color-management props.
# The virtual display now uses an LG CX EDID with HDR10 + BT2020 metadata,
# so the kernel at least reports an HDR-capable connector.
# To enable HDR we would need: a compositor with HDR support (KWin or Gamescope),
# KMS capture, and HEVC/AV1 10-bit.
{
  den.aspects.streaming = {
    nixos =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
        virtualDisplay = config.modules.virtualDisplay or { };
        connectorName = virtualDisplay.port or "DP-2";
        height = lib.last (lib.splitString "x" (virtualDisplay.resolution or "3840x2160"));
        refreshRate = toString (virtualDisplay.refreshRate or 120);
        sopsSecretPath =
          name:
          lib.attrByPath [
            "sops"
            "secrets"
            name
            "path"
          ] null config;
        sunshineApiEnvironment =
          lib.optional (
            sopsSecretPath "sunshineApiUsername" != null
          ) "SUNSHINE_API_USERNAME_FILE=${sopsSecretPath "sunshineApiUsername"}"
          ++ lib.optional (
            sopsSecretPath "sunshineApiPassword" != null
          ) "SUNSHINE_API_PASSWORD_FILE=${sopsSecretPath "sunshineApiPassword"}";
        niri-output-on = pkgs.writeShellApplication {
          name = "niri-output-on";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.gnused
            pkgs.jq
            pkgs.niri
            pkgs.procps
            pkgs.systemd
          ];
          text = ''
            export SUNSHINE_CONNECTOR_NAME=${lib.escapeShellArg connectorName}
          ''
          + builtins.readFile ./niri-output-on.sh;
        };
        steam-sunshine = pkgs.writeShellApplication {
          name = "steam-sunshine";
          runtimeInputs = [
            pkgs.bubblewrap
            pkgs.coreutils
            pkgs.gamemode
            pkgs.jq
            pkgs.procps
            pkgs.systemd
          ];
          text = ''
            export GAMESCOPE_HEIGHT=${height}
            export GAMESCOPE_REFRESH=${refreshRate}
            export SUNSHINE_CONNECTOR_NAME=${lib.escapeShellArg connectorName}
          ''
          + builtins.readFile ./sunshine-launch-common.sh
          + builtins.readFile ./steam-sunshine.sh;
        };
        heroic-sunshine = pkgs.writeShellApplication {
          name = "heroic-sunshine";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.gamemode
            pkgs.jq
            pkgs.procps
            pkgs.systemd
          ];
          text = ''
            export GAMESCOPE_HEIGHT=${height}
            export GAMESCOPE_REFRESH=${refreshRate}
            export SUNSHINE_CONNECTOR_NAME=${lib.escapeShellArg connectorName}
          ''
          + builtins.readFile ./sunshine-launch-common.sh
          + builtins.readFile ./heroic-sunshine.sh;
        };
        sunshine-stream-reset = pkgs.writeShellApplication {
          name = "sunshine-stream-reset";
          runtimeInputs = [
            pkgs.niri
            pkgs.procps
            pkgs.systemd
          ];
          text = ''
            connector_name=${lib.escapeShellArg connectorName}

            if [ -z "''${NIRI_SOCKET:-}" ]; then
              eval "$(systemctl --user show-environment | grep '^NIRI_SOCKET=' || true)"
              export NIRI_SOCKET
            fi
            niri msg output "$connector_name" off
            pkill -9 gamescope || true
            pkill -9 steam || true
            pkill -9 heroic || true
            pkill -f "systemd-inhibit.*--who=Sunshine" 2>/dev/null || true
          '';
        };
        sunshine-stream-cleanup = pkgs.writeShellApplication {
          name = "sunshine-stream-cleanup";
          runtimeInputs = [
            pkgs.curl
            pkgs.coreutils
          ];
          text = ''
            state_dir="''${XDG_RUNTIME_DIR:-/tmp}/sunshine-stream"
            close_marker="$state_dir/api-close-in-progress"
            mkdir -p "$state_dir"

            close_via_sunshine() {
              if [ -e "$close_marker" ]; then
                return 1
              fi

              touch "$close_marker"

              read_secret_file() {
                secret_file="$1"
                if [ -r "$secret_file" ]; then
                  tr -d '\r\n' < "$secret_file"
                fi
              }

              if [ -z "''${SUNSHINE_API_USERNAME:-}" ] && [ -n "''${SUNSHINE_API_USERNAME_FILE:-}" ]; then
                SUNSHINE_API_USERNAME="$(read_secret_file "$SUNSHINE_API_USERNAME_FILE")"
              fi

              if [ -z "''${SUNSHINE_API_PASSWORD:-}" ] && [ -n "''${SUNSHINE_API_PASSWORD_FILE:-}" ]; then
                SUNSHINE_API_PASSWORD="$(read_secret_file "$SUNSHINE_API_PASSWORD_FILE")"
              fi

              curl_args=(
                --insecure
                --silent
                --show-error
                --output /dev/null
                --write-out "%{http_code}"
                --request POST
                "https://localhost:47990/api/apps/close"
              )

              if [ -n "''${SUNSHINE_API_USERNAME:-}" ] && [ -n "''${SUNSHINE_API_PASSWORD:-}" ]; then
                curl_args=(--user "''${SUNSHINE_API_USERNAME}:''${SUNSHINE_API_PASSWORD}" "''${curl_args[@]}")
              fi

              status="$(curl "''${curl_args[@]}" 2>/dev/null || true)"
              echo "Sunshine close API returned HTTP status: ''${status:-none}"
              case "$status" in
                2*) return 0 ;;
                *) return 1 ;;
              esac
            }

            if close_via_sunshine; then
              sleep 20
            fi

            ${sunshine-stream-reset}/bin/sunshine-stream-reset
            rm -f "$close_marker" "$state_dir/managed-app-started"
          '';
        };
        sunshine-idle-watchdog = pkgs.writeShellApplication {
          name = "sunshine-idle-watchdog";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.gnused
            pkgs.systemd
          ];
          text = ''
            export SUNSHINE_IDLE_TIMEOUT_SECONDS=600
            export SUNSHINE_CLEANUP_COMMAND="${sunshine-stream-cleanup}/bin/sunshine-stream-cleanup"
          ''
          + builtins.readFile ./sunshine-idle-watchdog.sh;
        };
      in
      {
        sops.secrets = {
          sunshineApiUsername = {
            sopsFile = ../../../secrets/streaming.sops.yaml;
            owner = config.users.users.repparw.name;
            mode = "0400";
          };
          sunshineApiPassword = {
            sopsFile = ../../../secrets/streaming.sops.yaml;
            owner = config.users.users.repparw.name;
            mode = "0400";
          };
        };

        services.sunshine = {
          enable = true;
          openFirewall = true;
          capSysAdmin = false; # Disabled per https://github.com/NixOS/nixpkgs/issues/463989

          settings = {
            output_name = connectorName;
            min_log_level = "info";
            # Keep AMD hardware encoding and allow HEVC Main, but do not advertise Main10.
            encoder = "vaapi";
            hevc_mode = 2;
            av1_mode = 1;
          };

          applications = {
            env = {
              PATH = "/run/current-system/sw/bin:${config.users.users.repparw.home}/.local/bin";
            };
            apps = [
              {
                name = "Desktop";
                image-path = "desktop.png";
              }
              {
                name = "Steam Big Picture";
                detached = [ "${steam-sunshine}/bin/steam-sunshine" ];
                image-path = "steam.png";
                prep-cmd = [
                  {
                    do = "${niri-output-on}/bin/niri-output-on";
                    undo = "${sunshine-stream-reset}/bin/sunshine-stream-reset";
                  }
                ];
              }
              {
                name = "Heroic Games Launcher";
                detached = [ "${heroic-sunshine}/bin/heroic-sunshine" ];
                image-path = "heroic.png";
                prep-cmd = [
                  {
                    do = "${niri-output-on}/bin/niri-output-on";
                    undo = "${sunshine-stream-reset}/bin/sunshine-stream-reset";
                  }
                ];
              }
            ];
          };
        };

        systemd.user.services.sunshine-idle-watchdog = {
          description = "Clean up Sunshine streaming apps after client disconnect idle timeout";
          wantedBy = [ "sunshine.service" ];
          partOf = [ "sunshine.service" ];
          after = [ "sunshine.service" ];
          serviceConfig = {
            ExecStart = "${sunshine-idle-watchdog}/bin/sunshine-idle-watchdog";
            Environment = sunshineApiEnvironment;
            Restart = "always";
            RestartSec = "5s";
          };
        };
      };
  };
}
