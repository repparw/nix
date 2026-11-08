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

  # Browse leaves these runtime dependencies external in its npm bundle.
  ws = fetchurl {
    url = "https://registry.npmjs.org/ws/-/ws-8.22.0.tgz";
    hash = "sha512-Ydggc987+RO0AnWtZ/7Wq9FtNvcrL1b/RO0ud9mWjUPgDrsAAwQSF51sm2hm1XofbU/4jkpGEsLFsZZxU+1DOg==";
  };
  acorn = fetchurl {
    url = "https://registry.npmjs.org/acorn/-/acorn-8.18.0.tgz";
    hash = "sha512-lGq+9yr1/GuAWaVYIHRjvvySG5/4VfKIvC8EWxStPdcDh/Ka7FG3twP6v4d5BkravUilhIAsG4Qj83t02LWUPQ==";
  };
  pixelmatch = fetchurl {
    url = "https://registry.npmjs.org/pixelmatch/-/pixelmatch-7.2.0.tgz";
    hash = "sha512-xhcb4yHu9sM/G7foGzoLtXYcC0zHEaOXXjRKhGup0fw78Nf2Tkiapv4EQyMzrbcmQPsllAI7DbFY2UT7PlI9Pg==";
  };
  pngjs = fetchurl {
    url = "https://registry.npmjs.org/pngjs/-/pngjs-7.0.0.tgz";
    hash = "sha512-LKWqWJRhstyYo9pGvgor/ivk2w94eSjE3RGVuzLGlr3NmD8bf7RcYGze1mNdEHRP6TRP6rMuDHk5t44hnTRyow==";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/browse
    tar xzf $src -C $out/lib/browse --strip-components=1
    mkdir -p $out/lib/browse/node_modules/patchright-core
    tar xzf $patchrightCore -C $out/lib/browse/node_modules/patchright-core --strip-components=1
    for dep in ws acorn pixelmatch pngjs; do
      mkdir -p "$out/lib/browse/node_modules/$dep"
    done
    tar xzf "$ws" -C "$out/lib/browse/node_modules/ws" --strip-components=1
    tar xzf "$acorn" -C "$out/lib/browse/node_modules/acorn" --strip-components=1
    tar xzf "$pixelmatch" -C "$out/lib/browse/node_modules/pixelmatch" --strip-components=1
    tar xzf "$pngjs" -C "$out/lib/browse/node_modules/pngjs" --strip-components=1
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
      isc
    ];
    mainProgram = "browse";
    platforms = lib.platforms.linux;
  };
}
