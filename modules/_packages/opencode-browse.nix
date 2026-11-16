{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  jq,
  coreutils,
}:

let
  # The Rust CLI is published as one native npm package per platform.
  # The @opencode/browse npm package is now only a Node.js launcher.
  targets = {
    x86_64-linux = {
      name = "linux-x64";
      hash = "sha512-t7Tnc3PYMDIpJDl2Sq1+LQMtwGduNxJn04+z5SfoaNXOE5u8WXnRzgsFXUdXUrU+mhBUKomkuD1zWgl3AluzTQ==";
    };
    aarch64-linux = {
      name = "linux-arm64";
      hash = "sha512-wXcKVQPsXIK1xmLTv1ab/QMUStORyfF4j8I88SealM1pDWO5lXt3TbOK1CxtOc2wTUyiBPtQ0L40sX7pDmmsXQ==";
    };
    x86_64-darwin = {
      name = "darwin-x64";
      hash = "sha512-ulvfXzHDJt6BKkyzspW6GkRfIDrtqlAK/jiF1wAwHistCBqhrpCE4nEo5+jR+Jo/mwoFLg2nn4BQ0/OI1gwt8g==";
    };
    aarch64-darwin = {
      name = "darwin-arm64";
      hash = "sha512-ZCXEMP+Ewqs1yXc/a4LKzaNIzj33SFSYWpUaauiXPYkhyWq7T0oVmAI+D3SkbdGPjRwMIcqYc36g2wqcKwKKLw==";
    };
  };
  target = targets.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation (finalAttrs: {
  pname = "opencode-browse";
  version = "0.1.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@opencode/browse-${target.name}/-/browse-${target.name}-${finalAttrs.version}.tgz";
    inherit (target) hash;
  };

  sourceRoot = "package";
  dontBuild = true;

  nativeBuildInputs = [
    makeWrapper
    jq
    coreutils
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/browse "$out/bin/browse"
    runHook postInstall
  '';

  # Nix owns updates; do not let the upstream updater replace this binary.
  postFixup = ''
    wrapProgram "$out/bin/browse" --set OPENCODE_BROWSER_AUTO_UPDATE off
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    test "$("$out/bin/browse" --version)" = "${finalAttrs.version}"
    status=0
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"nixpkgs","version":"1"}}}' \
      | timeout 15 "$out/bin/browse" mcp > "$TMPDIR/initialize.json" || status=$?
    test "$status" -eq 0 || test "$status" -eq 130
    jq -se 'any(.[]; .id == 1 and .result.serverInfo.name == "browse" and .result.serverInfo.version == "${finalAttrs.version}")' \
      "$TMPDIR/initialize.json"
    runHook postInstallCheck
  '';

  meta = {
    description = "MCP server and CLI for automating a signed-in Chromium browser";
    homepage = "https://github.com/anomalyco/browse";
    changelog = "https://github.com/anomalyco/browse/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ repparw ];
    mainProgram = "browse";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames targets;
  };
})
