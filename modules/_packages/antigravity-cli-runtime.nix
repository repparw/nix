{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  writeShellScript,
  writeShellScriptBin,
  symlinkJoin,
  bash,
  coreutils,
  jq,
}:
let
  version = "1.5.9";

  sourceData = {
    x86_64-linux = {
      url = "https://github.com/google-antigravity/antigravity-cli/releases/download/1.5.9/agy_cli_linux_x64.tar.gz";
      hash = "sha256-ix9eVnefJDSgrzbxtxWoOSoITeVQ+MaLx5gh+V+r8/o=";
    };
    aarch64-linux = {
      url = "https://github.com/google-antigravity/antigravity-cli/releases/download/1.5.9/agy_cli_linux_arm64.tar.gz";
      hash = "sha256-OhjCOMfuZmHkPffoJKfUwb7Xiu7aCUMJIaDx2/6CW8o=";
    };
  };

  rawCli = stdenvNoCC.mkDerivation {
    pname = "antigravity-cli";
    inherit version;

    strictDeps = true;
    __structuredAttrs = true;

    src = fetchurl (
      sourceData.${stdenvNoCC.hostPlatform.system}
        or (throw "Unsupported system: ${stdenvNoCC.hostPlatform.system}")
    );

    nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isElf [ autoPatchelfHook ];

    sourceRoot = ".";

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 antigravity $out/libexec/agy

      runHook postInstall
    '';

    meta = {
      description = "Google Antigravity CLI";
      homepage = "https://antigravity.google";
      license = lib.licenses.unfree;
      platforms = lib.attrNames sourceData;
      mainProgram = "agy";
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  };

  launcher = writeShellScript "antigravity-agy-launch" ''
    set -euo pipefail

    if [ "$#" -lt 1 ]; then
      printf '%s\n' 'Antigravity CLI launcher: missing executable.' >&2
      exit 64
    fi

    real_cli=$1
    shift

    if [ "$#" -eq 0 ] || [ "$1" != "acp" ]; then
      exec "$real_cli" "$@"
    fi

    profile=''${GEMINI_HOME:-}
    if [ -z "$profile" ]; then
      printf '%s\n' 'Antigravity CLI launcher: GEMINI_HOME is not set.' >&2
      exit 64
    fi

    acp_directory="$profile/antigravity-acp"
    acp_token="$acp_directory/acp_token.json"
    cli_token="$acp_directory/antigravity-oauth-token"
    jq_bin=${jq}/bin/jq

    umask 077
    ${coreutils}/bin/mkdir -p "$acp_directory"
    ${coreutils}/bin/chmod 700 "$acp_directory"

    if [ -f "$acp_token" ]; then
      if ! "$jq_bin" -e '
        (.refresh_token | type) == "string"
        and (.refresh_token | length) > 0
      ' "$acp_token" >/dev/null; then
        printf '%s\n' 'Antigravity CLI launcher: the ACP credential is invalid.' >&2
        exit 65
      fi

      # shellcheck disable=SC2016
      if [ ! -f "$cli_token" ] || ! "$jq_bin" -e --slurpfile source "$acp_token" '
        (.auth_method == "consumer")
        and ((.token.refresh_token | type) == "string")
        and ((.token.refresh_token | length) > 0)
        and (.token.refresh_token == $source[0].refresh_token)
      ' "$cli_token" >/dev/null 2>&1; then
        temporary_token=$(${coreutils}/bin/mktemp "$acp_directory/.antigravity-oauth-token.XXXXXX")
        trap 'rm -f "$temporary_token"' EXIT

        "$jq_bin" '{
          auth_method: "consumer",
          token: {
            access_token: "",
            token_type: "Bearer",
            refresh_token: .refresh_token,
            expiry: "1970-01-01T00:00:00Z"
          }
        }' "$acp_token" >"$temporary_token"

        ${coreutils}/bin/chmod 600 "$temporary_token"
        ${coreutils}/bin/mv -f "$temporary_token" "$cli_token"
        trap - EXIT
      fi
    fi

    shift
    exec "$real_cli" acp \
      --gemini-dir "$profile" \
      --app-data-dir antigravity-acp \
      "$@"
  '';

  wrapper = writeShellScriptBin "agy" ''
    exec ${launcher} ${rawCli}/libexec/agy "$@"
  '';

  runtime = symlinkJoin {
    name = "antigravity-cli-runtime-${version}";
    paths = [
      rawCli
      wrapper
    ];
  };
in
{
  inherit
    launcher
    rawCli
    runtime
    version
    wrapper
    ;
}
