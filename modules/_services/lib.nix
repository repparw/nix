{
  lib,
  pkgs,
}:
let
  # Shared Discord poster for fleet services. Reads the bot token and channel
  # from the sops-provided hermes-env; `post` prints the message id on
  # success and fails otherwise, so callers can keep retryable state.
  discordNotifyText = ''
    if [ "$#" -lt 1 ]; then
      echo "usage: discord-notify post <content> | delete <message-id>" >&2
      exit 2
    fi
    cmd="$1"; shift

    # shellcheck disable=SC1091
    source /run/secrets/hermes-env
    if [ -z "''${DISCORD_BOT_TOKEN:-}" ]; then
      echo "discord-notify: DISCORD_BOT_TOKEN missing (hermes-env unreadable?)" >&2
      exit 1
    fi
    if [ -z "''${DISCORD_CHANNEL_ID:-}" ]; then
      echo "discord-notify: DISCORD_CHANNEL_ID not set" >&2
      exit 1
    fi
    api="https://discord.com/api/v10/channels/''$DISCORD_CHANNEL_ID/messages"

    case "$cmd" in
      post)
        content="''${1:-}"
        resp=$(curl -s -m 15 -w '\n%{http_code}' -X POST \
          -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
          -H "Content-Type: application/json" \
          -d "$(jq -n --arg c "$content" '{content: $c}')" "$api" || true)
        code=$(printf '%s' "$resp" | tail -n 1)
        mid=$(printf '%s' "$resp" | sed '$d' | jq -r '.id // empty' 2>/dev/null || true)
        if [ -n "$mid" ]; then
          echo "discord-notify: posted msg $mid (http $code)" >&2
          printf '%s' "$mid"
        else
          echo "discord-notify: POST failed (http $code)" >&2
          exit 1
        fi
        ;;
      delete)
        id="''${1:-}"
        code=$(curl -s -m 15 -o /dev/null -w '%{http_code}' -X DELETE \
          -H "Authorization: Bot $DISCORD_BOT_TOKEN" "$api/messages/$id" || echo curl-fail)
        case "$code" in
          200 | 204)
            echo "discord-notify: deleted msg $id (http $code)" >&2
            ;;
          # 404 Unknown Message means the message is already gone, which is the
          # state the caller asked for. Treating it as retryable pinned the
          # msgid file forever: every probe re-attempted a deletion that can
          # never succeed. Exiting zero lets the caller clear its own state.
          # A 5xx or a transport failure stays retryable, because the message
          # may well still be there.
          404)
            echo "discord-notify: msg $id already absent (http 404), treating as cleared" >&2
            ;;
          *)
            echo "discord-notify: DELETE failed: msg $id http=$code (msgid kept for retry)" >&2
            exit 1
            ;;
        esac
        ;;
      *)
        echo "usage: discord-notify post <content> | delete <message-id>" >&2
        exit 2
        ;;
    esac
  '';
  serviceUrl =
    cfg: hostConfig: name:
    let
      service = cfg.definitions.${name};
      target =
        if service.host != cfg.hostName then
          "${cfg.hostAddresses.${service.host}}:${
            toString (if service.publishedPort != null then service.publishedPort else service.port)
          }"
        else if
          lib.hasAttr name hostConfig.containers && hostConfig.containers.${name}.localAddress != null
        then
          "${hostConfig.containers.${name}.localAddress}:${toString service.port}"
        else
          "127.0.0.1:${toString service.port}";
    in
    "http://${target}";

  backupServices = cfg: lib.filterAttrs (_: service: service.backup != null) cfg.definitions;

  backupMountUnit = name: "home-containers-backup-${name}.mount";

  publicHealthUrl =
    cfg: hostConfig: name:
    let
      service = cfg.definitions.${name};
    in
    if service.healthcheck != null then
      "https://${service.hostname}.${cfg.domain}${service.healthcheck}"
    else
      serviceUrl cfg hostConfig name;
in
{
  inherit serviceUrl publicHealthUrl;

  mkDiscordNotify =
    pkgs_:
    pkgs_.writeShellApplication {
      name = "discord-notify";
      runtimeInputs = with pkgs_; [
        curl
        jq
        gnused
      ];
      text = discordNotifyText;
    };

  serviceHosts =
    cfg:
    lib.mapAttrsToList (_: service: "${service.hostname}.${cfg.domain}") (
      lib.filterAttrs (_: service: service.hostname != null) cfg.definitions
    );

  monitorSites =
    cfg: hostConfig:
    lib.mapAttrsToList
      (
        name: service:
        if service.healthcheck != null then
          {
            title = name;
            url = "https://${service.hostname}.${cfg.domain}";
            check-url = publicHealthUrl cfg hostConfig name;
            timeout = "10s";
          }
        else
          {
            title = name;
            url = "https://${service.hostname}.${cfg.domain}";
            check-url = serviceUrl cfg hostConfig name;
            timeout = "10s";
            alt-status-codes = [ 302 ];
          }
      )
      (
        lib.filterAttrs (
          _: service: service.monitor && service.hostname != null && service.port != null
        ) cfg.definitions
      );

  backupMounts =
    cfg:
    lib.mapAttrs' (
      name: service:
      lib.nameValuePair "${cfg.backupDir}/${name}" {
        depends = [ "/" ];
        device = service.backup.path;
        fsType = "none";
        options = [
          "bind"
          "ro"
          "nofail"
        ];
      }
    ) (backupServices cfg);

  containerBackupAfters =
    cfg:
    lib.mapAttrs' (
      name: _: lib.nameValuePair "container@${name}" { after = [ (backupMountUnit name) ]; }
    ) (backupServices cfg);

  backupAfter = names: map backupMountUnit names;

  mkContainer =
    {
      cfg,
      name,
      hostAddress ? null,
      privateUsers ? null,
      bindMounts ? { },
      allowedDevices ? [ ],
      extraFlags ? [ ],
      forwardPorts ? [ ],
      serviceConfig ? { },
      extraConfig ? { },
      extraOptions ? { },
      imports ? [ ],
    }:
    let
      effectiveHost = if hostAddress != null then hostAddress else "${cfg.bridgePrefix}.1";
    in
    {
      autoStart = true;
      privateNetwork = true;
      hostAddress = lib.mkDefault effectiveHost;
      inherit extraFlags;
      config =
        { pkgs, ... }@args:
        {
          inherit imports;
          config = lib.mkMerge [
            {
              services = serviceConfig;
              networking.useHostResolvConf = false;
              networking.nameservers = lib.mkDefault [ effectiveHost ];
              system.stateVersion = "26.05";
            }
            (if builtins.isFunction extraConfig then extraConfig args else extraConfig)
          ];
        };
    }
    // lib.optionalAttrs (privateUsers != null) { inherit privateUsers; }
    // lib.optionalAttrs (bindMounts != { }) { inherit bindMounts; }
    // lib.optionalAttrs (allowedDevices != [ ]) { inherit allowedDevices; }
    // lib.optionalAttrs (forwardPorts != [ ]) { inherit forwardPorts; }
    // extraOptions;

  mkBackupJob =
    {
      name,
      description,
      backupDir,
      filePattern,
      createBackup,
      owner ? null,
      group ? owner,
      retention ? 7,
      onCalendar ? "daily",
      randomizedDelaySec ? "30min",
      serviceConfig ? { },
    }:
    let
      pruneBackups = pkgs.writeShellApplication {
        name = "${name}-prune-backups";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
        ];
        text = ''
          set -euo pipefail
          cd "${backupDir}"
          find . -maxdepth 1 -type f -name '${filePattern}' -printf '%T@ %p\0' \
            | sort -z -rn \
            | tail -z -n +${toString (retention + 1)} \
            | cut -z -d ' ' -f 2- \
            | xargs -0 -r rm -v
        '';
      };

      installBackupDir = lib.optionalAttrs (owner != null) {
        ExecStartPre = "+${lib.getExe' pkgs.coreutils "install"} -d -m 0750 -o ${owner} -g ${group} ${backupDir}";
      };
    in
    {
      systemd.services."${name}-backup" = {
        description = "Create ${description} backup";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe createBackup;
          ExecStartPost = lib.getExe pruneBackups;
        }
        // installBackupDir
        // serviceConfig;
        wantedBy = [ ];
      };

      systemd.timers."${name}-backup" = {
        description = "Run ${description} backup";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = onCalendar;
          Persistent = true;
          RandomizedDelaySec = randomizedDelaySec;
        };
      };
    };
}
