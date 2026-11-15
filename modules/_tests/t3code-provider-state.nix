{ pkgs }:
let
  providerState = import ../_packages/t3code-provider-state.nix { inherit pkgs; };
in
pkgs.runCommand "check-t3code-provider-state"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.jq
      pkgs.shellcheck
    ];
  }
  ''
    ${pkgs.shellcheck}/bin/shellcheck ${providerState.cleanupScript}

    home=$(mktemp -d)
    settings="$home/.t3/userdata/settings.json"
    caches="$home/.t3/caches"
    mkdir -p "$(dirname "$settings")" "$caches"
    cat >"$settings" <<'JSON'
    {
      "theme": "keep-me",
      "providerInstances": {
        "antigravity": {},
        "antigravity_2": {},
        "claudeAgent": {},
        "codex": {},
        "codex_2": {},
        "grok": {},
        "opencode": {}
      }
    }
    JSON
    printf '%s\n' stale >"$caches/grok.json"
    printf '%s\n' stale >"$caches/claudeAgent.json"
    printf '%s\n' keep >"$caches/codex.json"

    allowed='["antigravity","antigravity_2","codex","codex_2","opencode"]'
    stamp="$home/.t3/userdata/provider-instances.sha256"
    result=$(${providerState.cleanupScript} "$settings" "$caches" "$allowed" "$stamp")
    test "$result" = changed

    jq -e '
      .theme == "keep-me"
      and (.providerInstances | keys) == [
        "antigravity",
        "antigravity_2",
        "codex",
        "codex_2",
        "opencode"
      ]
    ' "$settings" >/dev/null
    test ! -e "$caches/grok.json"
    test ! -e "$caches/claudeAgent.json"
    test -e "$caches/codex.json"

    printf '%s\n' stale >"$caches/grok.json"
    printf '%s\n' stale >"$caches/claudeAgent.json"
    ${providerState.cleanupScript} "$settings" "$caches" "$allowed" "$stamp"
    test ! -e "$caches/grok.json"
    test ! -e "$caches/claudeAgent.json"

    result=$(${providerState.cleanupScript} "$settings" "$caches" "$allowed" "$stamp")
    test "$result" = unchanged

    touch $out
  ''
