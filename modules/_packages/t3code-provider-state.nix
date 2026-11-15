{ pkgs }:
let
  cleanupScript = pkgs.writeShellScript "t3code-provider-state-cleanup" ''
    set -euo pipefail

    if [ "$#" -ne 4 ]; then
      printf '%s\n' 'Usage: t3code-provider-state-cleanup SETTINGS CACHE_DIR ALLOWED_JSON STAMP' >&2
      exit 64
    fi

    settings=$1
    cache_directory=$2
    allowed_instances=$3
    state_stamp=$4

    if [ ! -f "$settings" ]; then
      printf '%s\n' 'T3 Code settings file does not exist.' >&2
      exit 66
    fi

    temporary_settings=$(${pkgs.coreutils}/bin/mktemp "$settings.tmp.XXXXXX")
    trap 'rm -f "$temporary_settings"' EXIT

    ${pkgs.jq}/bin/jq --argjson allowed "$allowed_instances" '
      .providerInstances = (
        (.providerInstances // {})
        | with_entries(select(.key as $key | $allowed | index($key)))
      )
    ' "$settings" >"$temporary_settings"

    ${pkgs.coreutils}/bin/chmod 600 "$temporary_settings"
    ${pkgs.coreutils}/bin/mv -f "$temporary_settings" "$settings"
    trap - EXIT

    ${pkgs.coreutils}/bin/rm -f \
      "$cache_directory/grok.json" \
      "$cache_directory/claudeAgent.json"

    provider_hash=$(
      ${pkgs.jq}/bin/jq -cS '.providerInstances' "$settings" \
        | ${pkgs.coreutils}/bin/sha256sum \
        | ${pkgs.coreutils}/bin/cut -d " " -f 1
    )
    previous_hash=$(${pkgs.coreutils}/bin/cat "$state_stamp" 2>/dev/null || true)

    if [ "$provider_hash" != "$previous_hash" ]; then
      temporary_stamp=$(${pkgs.coreutils}/bin/mktemp "$state_stamp.tmp.XXXXXX")
      trap 'rm -f "$temporary_stamp"' EXIT
      printf '%s\n' "$provider_hash" >"$temporary_stamp"
      ${pkgs.coreutils}/bin/chmod 600 "$temporary_stamp"
      ${pkgs.coreutils}/bin/mv -f "$temporary_stamp" "$state_stamp"
      trap - EXIT
      printf '%s\n' changed
    else
      printf '%s\n' unchanged
    fi
  '';
in
{
  inherit cleanupScript;
}
