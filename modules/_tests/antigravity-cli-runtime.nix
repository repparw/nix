{ pkgs }:
let
  runtime = pkgs.callPackage ../_packages/antigravity-cli-runtime.nix { };

  mcpRuntime = pkgs.callPackage ../_packages/antigravity-cli-runtime.nix {
    mcpConfig = pkgs.writeText "profile-mcp-config.json" (
      builtins.toJSON {
        mcpServers.nixos = {
          command = "/bin/mcp-nixos";
          args = [ ];
          env = { };
        };
      }
    );
  };
in
pkgs.runCommand "check-antigravity-cli-runtime"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.diffutils
      pkgs.jq
      pkgs.shellcheck
    ];
  }
  ''
    ${pkgs.shellcheck}/bin/shellcheck ${runtime.launcher}

    profile=$(mktemp -d)
    mkdir -p "$profile/antigravity-acp"
    cat >"$profile/antigravity-acp/acp_token.json" <<'JSON'
    {
      "client_id": "fixture-client",
      "client_secret": "fixture-secret",
      "refresh_token": "first-refresh-token"
    }
    JSON

    fake_cli="$profile/fake-agy"
    arguments="$profile/arguments"
    cat >"$fake_cli" <<'SH'
    #!/bin/sh
    printf '%s\n' "$@" >"$ARGS_FILE"
    SH
    chmod +x "$fake_cli"

    GEMINI_HOME="$profile" ARGS_FILE="$arguments" \
      ${runtime.launcher} "$fake_cli" acp --extra value

    {
      printf '%s\n' \
        acp \
        --gemini-dir \
        "$profile" \
        --app-data-dir \
        antigravity-acp \
        --extra \
        value
    } >"$profile/expected-arguments"
    diff -u "$profile/expected-arguments" "$arguments"

    cli_token="$profile/antigravity-acp/antigravity-oauth-token"
    jq -e '
      .auth_method == "consumer"
      and .token.access_token == ""
      and .token.token_type == "Bearer"
      and .token.refresh_token == "first-refresh-token"
      and .token.expiry == "1970-01-01T00:00:00Z"
    ' "$cli_token" >/dev/null
    test "$(stat -c %a "$cli_token")" = 600

    jq '.refresh_token = "second-refresh-token"' \
      "$profile/antigravity-acp/acp_token.json" \
      >"$profile/antigravity-acp/acp_token.json.new"
    mv "$profile/antigravity-acp/acp_token.json.new" \
      "$profile/antigravity-acp/acp_token.json"
    GEMINI_HOME="$profile" ARGS_FILE="$arguments" \
      ${runtime.launcher} "$fake_cli" acp
    jq -e '.token.refresh_token == "second-refresh-token"' "$cli_token" >/dev/null

    unsigned_profile=$(mktemp -d)
    GEMINI_HOME="$unsigned_profile" ARGS_FILE="$arguments" \
      ${runtime.launcher} "$fake_cli" acp
    test ! -e "$unsigned_profile/antigravity-acp/antigravity-oauth-token"

    invalid_profile=$(mktemp -d)
    mkdir -p "$invalid_profile/antigravity-acp"
    printf '%s\n' '{}' >"$invalid_profile/antigravity-acp/acp_token.json"
    if GEMINI_HOME="$invalid_profile" ARGS_FILE="$arguments" \
      ${runtime.launcher} "$fake_cli" acp; then
      printf '%s\n' 'Invalid ACP credentials must fail before ACP starts.' >&2
      exit 1
    fi
    test ! -e "$invalid_profile/antigravity-acp/antigravity-oauth-token"

    fake_home=$(mktemp -d)
    mkdir -p "$fake_home/.gemini/config/skills" "$fake_home/.gemini/config/rules"
    linked_profile=$(mktemp -d)
    mkdir -p "$linked_profile/config/skills"
    HOME="$fake_home" GEMINI_HOME="$linked_profile" ARGS_FILE="$arguments" \
      ${runtime.launcher} "$fake_cli" acp
    test "$(readlink "$linked_profile/config/skills")" = "$fake_home/.gemini/config/skills"
    test "$(readlink "$linked_profile/config/rules")" = "$fake_home/.gemini/config/rules"

    custom_profile=$(mktemp -d)
    mkdir -p "$custom_profile/config/skills"
    touch "$custom_profile/config/skills/local-only"
    HOME="$fake_home" GEMINI_HOME="$custom_profile" ARGS_FILE="$arguments" \
      ${runtime.launcher} "$fake_cli" acp
    test ! -L "$custom_profile/config/skills"
    test -f "$custom_profile/config/skills/local-only"
    test "$(readlink "$custom_profile/config/rules")" = "$fake_home/.gemini/config/rules"

    mcp_profile=$(mktemp -d)
    HOME="$fake_home" GEMINI_HOME="$mcp_profile" ARGS_FILE="$arguments" \
      ${mcpRuntime.launcher} "$fake_cli" acp
    # A regular file, not a symlink: the T3 Code text-generation gate
    # rejects symlinks when reading profile MCP config.
    test -f "$mcp_profile/config/mcp_config.json"
    test ! -L "$mcp_profile/config/mcp_config.json"
    jq -e '.mcpServers.nixos.command == "/bin/mcp-nixos"' \
      "$mcp_profile/config/mcp_config.json" >/dev/null
    test "$(stat -c %a "$mcp_profile/config/mcp_config.json")" = 600

    # Declarative config wins over manual edits on every launch.
    printf 'stale\n' >"$mcp_profile/config/mcp_config.json"
    HOME="$fake_home" GEMINI_HOME="$mcp_profile" ARGS_FILE="$arguments" \
      ${mcpRuntime.launcher} "$fake_cli" acp
    jq -e '.mcpServers.nixos' "$mcp_profile/config/mcp_config.json" >/dev/null

    # Without a fleet MCP config the profile keeps whatever it had.
    plain_profile=$(mktemp -d)
    HOME="$fake_home" GEMINI_HOME="$plain_profile" ARGS_FILE="$arguments" \
      ${runtime.launcher} "$fake_cli" acp
    test ! -e "$plain_profile/config/mcp_config.json"

    touch $out
  ''
