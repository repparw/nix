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
            # Read structured output to match the exact client label. Multiple
            # matching sessions are ambiguous: alpha cannot determine which
            # bearer token Hermes has loaded on epsilon.
            sessions=$(runuser -u repparw -- ${pkgs.t3code}/bin/t3 auth session list --json 2>&1) || {
              echo "t3-token-watch: t3 auth session list failed: $sessions" >&2
              exit 1
            }
            matches=$(printf '%s\n' "$sessions" | jq -c --arg label "${sessionLabel}" '
              if type != "array" then error("expected session array")
              else [ .[] | select(.client.label == $label) | {sessionId, expiresAt} ]
              end
            ') || {
              echo "t3-token-watch: invalid t3 auth session list JSON" >&2
              exit 1
            }
            count=$(printf '%s\n' "$matches" | jq 'length')
            now=$(date +%s)

            if (( count == 0 )); then
              band=missing
              detail="No active T3 mcp-client session labeled \`${sessionLabel}\` was found on alpha. Verify Hermes MCP before revoking any credentials."
            elif (( count > 1 )); then
              band=overlap
              detail="$count active T3 MCP sessions labeled \`${sessionLabel}\` exist on alpha. The watcher cannot identify the token Hermes on epsilon is using. Deploy epsilon, verify a real Hermes-to-T3 MCP request, then revoke the old session. Do not treat the later expiry as proof of healthy authentication."
            else
              session_id=$(printf '%s\n' "$matches" | jq -r '.[0].sessionId')
              verified_id=$(cat "$state_dir/verified-session-id" 2>/dev/null || true)
              if [ -z "$session_id" ] || [ "$session_id" = null ]; then
                echo "t3-token-watch: matching session has no session ID" >&2
                exit 1
              fi
              expiry=$(printf '%s\n' "$matches" | jq -r '.[0].expiresAt')
              expiry_epoch=$(date -d "$expiry" +%s) || {
                echo "t3-token-watch: cannot parse expiry '$expiry'" >&2
                exit 1
              }
              remaining=$((expiry_epoch - now))
              days=$((remaining / 86400))
              if [ "$session_id" != "$verified_id" ]; then
                band=unverified
                detail="The sole T3 MCP session labeled \`${sessionLabel}\` has not been verified against Hermes on epsilon (expires $expiry, $days day(s) remaining). Run a real Hermes-initiated MCP request, then acknowledge the session ID on alpha as documented in the secret inventory. Do not assume the token currently used by Hermes is valid."
              elif (( remaining <= 0 )); then
                band=expired
              elif (( days < 2 )); then
                band=critical
              elif (( days < 7 )); then
                band=warn
              else
                band=ok
              fi
              if [ "$band" != unverified ]; then
                detail="Verified T3 MCP session on alpha expires $expiry ($days day(s) remaining). This check does not replace an actual Hermes MCP health probe."
              fi
            fi

            # Threshold warnings fire once per band. Unverified credentials
            # and unresolved overlaps repeat weekly until the operator checks
            # the real Hermes MCP connection and completes the rotation.
            # Persist notification state only after posting successfully.
            last=$(cat "$state_file" 2>/dev/null || true)
            if [ "$band" = "$last" ]; then
              if [ "$band" != overlap ] && [ "$band" != unverified ]; then
                exit 0
              fi
              last_reminder=$(cat "$state_dir/last-credential-notice" 2>/dev/null || echo 0)
              if [[ "$last_reminder" =~ ^[0-9]+$ ]] && (( now - last_reminder < 604800 )); then
                exit 0
              fi
            fi
            if [ "$band" = ok ]; then
              printf '%s\n' "$band" > "$state_file"
              exit 0
            fi

            case "$band" in
              missing) header="🔴 T3 MCP session missing" ;;
              overlap) header="🟡 T3 MCP session rotation incomplete" ;;
              unverified) header="🟡 T3 MCP session not verified on epsilon" ;;
              expired) header="🔴 T3 MCP token expired" ;;
              critical) header="🔴 T3 MCP token expires in under 2 days" ;;
              warn) header="🟡 T3 MCP token expires within 7 days" ;;
            esac
            renew="Renew: on alpha, issue a fresh \`mcp-client\` session (orchestration:read + orchestration:operate, 365d), update \`T3_MCP_TOKEN\` in the SOPS \`hermes-llm-env\` value, deploy epsilon, verify Hermes MCP, then revoke the old session."
            discord-notify post "$(printf '%s\n%s\n%s' "$header" "$detail" "$renew")" >/dev/null
            printf '%s\n' "$band" > "$state_file"
            if [ "$band" = overlap ] || [ "$band" = unverified ]; then
              printf '%s\n' "$now" > "$state_dir/last-credential-notice"
            fi
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
