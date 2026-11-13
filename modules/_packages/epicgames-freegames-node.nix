{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_26,
}:
# Device-auth Epic claiming portal (claabs/epicgames-freegames-node), the
# trial from issue #521: detects free Epic games through the catalog API and
# sends a prepopulated checkout link to Discord instead of driving the
# Cloudflare-protected storefront checkout. Runs from source on Node 26
# (native TypeScript), like upstream's Docker entrypoint.
(buildNpmPackage {
  pname = "epicgames-freegames-node";
  version = "6.0.0-unstable-2026-11-09";

  src = fetchFromGitHub {
    owner = "claabs";
    repo = "epicgames-freegames-node";
    rev = "a90b92b906ecf0ba348ece2730ee5f17ff8b859a";
    hash = "sha256-HVsjXJxHpDSzej7AJJGJYBJ2L9xAJEO0kkRKTNf2uAQ=";
  };

  nodejs = nodejs_26;
  npmDepsHash = "sha256-NCBA43wCdHAA1lT1pqS+MxMO35eMg9H4tNPnEzDCQrU=";
  dontNpmBuild = true;

  # Neither dependency may download browsers during npm ci: the runtime
  # engine is patchright, pointed at the Nixpkgs Chromium with BROWSER_PATH
  # at run time (same approach as free-games-claimer's FGC_CHROME_PATH).
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  PATCHRIGHT_SKIP_BROWSER_DOWNLOAD = "1";

  postPatch = ''
    substituteInPlace src/common/playwright.ts \
      --replace-fail "channel: os.arch() === 'arm64' ? 'chromium' : 'chrome'," \
        "executablePath: process.env.BROWSER_PATH,"
  '';

  # buildNpmPackage installs to lib/node_modules, but Node 26 refuses to
  # type-strip any TypeScript under a node_modules path
  # (ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING) and upstream runs its own
  # TypeScript entrypoint directly. Relocate the app (with its bundled
  # dependencies) to share/, where the entrypoint is stripped normally.
  postInstall = ''
    mkdir -p "$out/share"
    mv "$out/lib/node_modules/epicgames-freegames-node" "$out/share/epicgames-freegames-node"
    rmdir --ignore-fail-on-non-empty "$out/lib/node_modules" "$out/lib" 2>/dev/null || true
  '';

  meta = {
    description = "Detects free Epic Games Store games and sends a device-auth/checkout link";
    homepage = "https://github.com/claabs/epicgames-freegames-node";
    license = lib.licenses.mit;
  };
})
