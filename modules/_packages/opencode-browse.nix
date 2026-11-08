{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  nodejs-runtime,
}:

stdenv.mkDerivation {
  pname = "opencode-browse";
  version = "0.0.15";

  src = fetchurl {
    url = "https://registry.npmjs.org/@opencode/browse/-/browse-0.0.15.tgz";
    hash = "sha256-TUb6MjrpUVzTSPlPPIUJ8FzPE7rVI0O3h4KhhRLtqo4=";
  };

  patchrightCore = fetchurl {
    url = "https://registry.npmjs.org/patchright-core/-/patchright-core-1.63.0.tgz";
    hash = "sha256-iRizxHd+UfZP0SFDxgC0Kw2wI0R1MtYgfNUtiAPErmw=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/browse
    tar xzf $src -C $out/lib/browse --strip-components=1
    mkdir -p $out/lib/browse/node_modules/patchright-core
    tar xzf $patchrightCore -C $out/lib/browse/node_modules/patchright-core --strip-components=1
    mkdir -p $out/bin
    makeWrapper ${nodejs-runtime}/bin/node $out/bin/browse \
      --add-flags "$out/lib/browse/dist/cli.mjs" \
      --set NODE_PATH "$out/lib/browse/node_modules" \
      --set OPENCODE_BROWSER_AUTO_UPDATE off
    ln -s browse $out/bin/opencode-browser
    ln -s browse $out/bin/opencode-browser-cli
    runHook postInstall
  '';

  meta = {
    description = "MCP server and CLI to drive the user's real Chromium browser via extension";
    homepage = "https://github.com/anomalyco/browse";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "browse";
    platforms = lib.platforms.linux;
  };
}
