{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
# Fork of vogler/free-games-claimer carrying the patchright migration that
# keeps Epic/GOG claiming functional as of 2026-09; pinned to a known-good
# revision. Runtime browser is Nixpkgs Chromium via FGC_CHROME_PATH (see the
# free-games-claimer service aspect), not the branded Chrome the upstream
# Docker image downloads.
(buildNpmPackage {
  pname = "free-games-claimer";
  version = "1.4.0-unstable-2026-09-21";

  src = fetchFromGitHub {
    owner = "FroggMaster";
    repo = "free-games-claimer";
    rev = "dc756d6244c323219a7be5d7ac0abcfe4a2fcc96";
    hash = "sha256-RKu04xT4N8uxaWrCiHN/O9thYgiicFPXRhkCh7lsIFw=";
  };

  npmDepsHash = "sha256-wrKbkiVt+cg0ziF6w33TH4qij6Jd1Lmb/+JNRIjnreU=";

  # The package has no build step; the store scripts are run directly.
  dontNpmBuild = true;

  # The storefront scripts request branded Chrome (`channel: 'chrome'`).
  # Branded Chrome has no aarch64 Linux build and its install path assumes a
  # system package manager, so route every launch through an explicit
  # executable instead; the service sets FGC_CHROME_PATH.
  postPatch = ''
    substituteInPlace aliexpress.js epic-games.js gog.js prime-gaming.js \
      steam-games.js steam.js unrealengine.js \
      --replace-fail "channel: 'chrome'," \
        "executablePath: process.env.FGC_CHROME_PATH,"

    # Keep the package in the Nix store and redirect only mutable browser data.
    substituteInPlace src/util.js \
      --replace-fail "path.resolve(__dirname, '..', 'data', s)" \
        "path.resolve(process.env.FGC_DATA_DIR || path.resolve(__dirname, '..', 'data'), s)"

    # GOG persists the first error indefinitely unless statuses are updated.
    # Allow later claims or already-owned results to clear stale failures.
    substituteInPlace gog.js \
      --replace-fail "db.data[user][title].status ||= status;" \
        "db.data[user][title].status = status;"

    # Test native headless first. The service's SHOW=1 switch restores headed.
    substituteInPlace epic-games.js gog.js \
      --replace-fail "headless: false," "headless: cfg.headless,"

    # No terminal is available during scheduled runs; fail promptly if the
    # persistent profile needs interactive authentication.
    substituteInPlace epic-games.js \
      --replace-fail "console.error('Not signed in anymore. Please login in the browser or here in the terminal.');" \
        "if (cfg.headless) throw new Error('Epic: saved session expired; headed login required.'); console.error('Not signed in anymore. Please login in the browser or here in the terminal.');"
    substituteInPlace gog.js \
      --replace-fail "console.error('Not signed in anymore.');" \
        "if (cfg.headless) throw new Error('GOG: saved session expired; headed login required.'); console.error('Not signed in anymore.');" \
      --replace-fail "console.error('Could not determine GOG login state - page structure changed?');" \
        "throw new Error('GOG: cannot determine saved login state.');"

    # Exit 75 signals transient claim failure; other errors exit 1.
    substituteInPlace epic-games.js gog.js \
      --replace-fail "process.exitCode ||= 1;" "process.exitCode ||= user ? 75 : 1;"
    substituteInPlace epic-games.js \
      --replace-fail "db.data[user][game_id].status = 'failed';" \
        "db.data[user][game_id].status = 'failed'; process.exitCode ||= 75;" \
      --replace-fail "console.error('  Got hcaptcha challenge! Lost trust due to too many login attempts? You can solve the captcha in the browser or get a new IP address.');" \
        "process.exitCode = 1; console.error('  Got hcaptcha challenge! Lost trust due to too many login attempts? You can solve the captcha in the browser or get a new IP address.');"
    substituteInPlace gog.js \
      --replace-fail "notify_games.push({ title, url, status });" \
        "if (status === 'Unauthorized') process.exitCode ||= 1; else if (!['claimed', 'existed', 'Giveaway has ended'].includes(status)) process.exitCode ||= 75; notify_games.push({ title, url, status });"
  '';

  meta = {
    description = "Automatically claims free games on the Epic Games Store and GOG";
    homepage = "https://github.com/FroggMaster/free-games-claimer";
    license = lib.licenses.agpl3Only;
  };
})
