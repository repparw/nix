{
  lib,
  pkgs,
  ...
}:
let
  mkDiscordNotify = (import ../../_services/lib.nix { inherit lib pkgs; }).mkDiscordNotify;
in
{
  den.aspects.nixos-services.provides.t3-token-watch = {
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.modules.services;
        # The Hermes T3 MCP session is provisioned with this label; rotation
        # must reuse it so this watcher keeps matching the live credential.
        sessionLabel = "hermes-t3-mcp";
        tokenWatch = pkgs.writeShellApplication {
          name = "t3-token-watch";
          runtimeInputs = with pkgs; [
            coreutils
            gawk
            gnugrep
            gnused
            jq
            util-linux
            (mkDiscordNotify pkgs cfg.discordChannelId)
          ];
          text = ''
            state_dir="''${STATE_DIRECTORY:-/var/lib/t3-token-watch}"
            state_file="$state_dir/last-band"

            # The watcher runs as root for /run/secrets/hermes-env, but the T3
            # state directory belongs to repparw: list sessions through that
            # account instead of touching the live server state as root.
            # pkgs.t3code resolves through the t3code-stable010 overlay that
            # alpha's repparw aspect applies; this watcher is alpha-only.
            export HOME=/home/repparw
            export T3CODE_HOME=/home/repparw/.t3
            list=$(runuser -u repparw -- ${pkgs.t3code}/bin/t3 auth session list 2>&1) || {
              echo "t3-token-watch: t3 auth session list failed: $list" >&2
              exit 1
            }

            # Sessions print as blocks: subject and client precede expires.
            # Rotation may briefly hold two labeled sessions; the newest
            # expiry is the one that matters. ISO timestamps sort lexically.
            expiry=$(printf '%s\n' "$list" | awk '
              /^  client: ${sessionLabel}/ { seen = 1 }
              seen && /^  expires: / {
                line = $0
                sub(/^  expires: /, "", line)
                print line
                seen = 0
              }
            ' | sort | tail -1)

            if [ -z "$expiry" ]; then
              band=missing
              detail="No active T3 mcp-client session labeled \`${sessionLabel}\` was found on alpha. Hermes T3 orchestration is unauthenticated; provision a replacement before revoking anything else."
            else
              expiry_epoch=$(date -d "$expiry" +%s) || {
                echo "t3-token-watch: cannot parse expiry '$expiry'" >&2
                exit 1
              }
              now=$(date +%s)
              remaining=$((expiry_epoch - now))
              days=$((remaining / 86400))
              if (( remaining <= 0 )); then
                band=expired
              elif (( days < 2 )); then
                band=critical
              elif (( days < 7 )); then
                band=warn
              else
                band=ok
              fi
              detail="T3 MCP token (Hermes on epsilon → alpha) expires $expiry — $days day(s) remaining."
            fi

            # One post per threshold band, so a week inside warn is one
            # reminder plus the escalation, not seven.
            last=$(cat "$state_file" 2>/dev/null || true)
            if [ "$band" = "$last" ]; then
              exit 0
            fi
            echo "$band" > "$state_file"
            if [ "$band" = ok ]; then
              exit 0
            fi

            case "$band" in
              missing) header="🔴 T3 MCP session missing" ;;
              expired) header="🔴 T3 MCP token expired" ;;
              critical) header="🔴 T3 MCP token expires in under 2 days" ;;
              warn) header="🟡 T3 MCP token expires within 7 days" ;;
            esac
            renew="Renew: on alpha, issue a fresh \`mcp-client\` session (orchestration:read + orchestration:operate, ≤30d), update \`T3_MCP_TOKEN\` in the SOPS \`hermes-llm-env\` value, deploy epsilon, verify Hermes MCP, then revoke the old session."
            discord-notify post "$(printf '%s\n%s\n%s' "$header" "$detail" "$renew")" >/dev/null
          '';
        };
      in
      {
        systemd.services.t3-token-watch = {
          description = "Warn Discord before the Hermes T3 MCP token expires";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          environment.DISCORD_CHANNEL_ID = cfg.discordChannelId;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe tokenWatch;
            StateDirectory = "t3-token-watch";
          };
        };

        systemd.timers.t3-token-watch = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            # Daily scan; the script deduplicates per band.
            OnCalendar = "daily";
            Persistent = true;
          };
        };
      };
  };
}
