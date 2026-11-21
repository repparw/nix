{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
}:
let
  # Upstream dev still uses GOG's retired menuUsername login selector.
  gogScript = fetchurl {
    url = "https://raw.githubusercontent.com/FroggMaster/free-games-claimer/dc756d6244c323219a7be5d7ac0abcfe4a2fcc96/gog.js";
    hash = "sha256-Wlwrtuq8C2IZKurYd+iSDUl7QWgT1iJ9MSXlntaUC8Y=";
  };
in
buildNpmPackage {
  pname = "free-games-claimer";
  version = "1.4.0-unstable-2026-11-05";

  src = fetchFromGitHub {
    owner = "vogler";
    repo = "free-games-claimer";
    rev = "ecac99e583d3a100db8668953081c8af1df7356d";
    hash = "sha256-GU+Y8ZZBGapYDAhDH54fmpGYIFbl1vNe8Ir5hlq2rm4=";
  };

  npmDepsHash = "sha256-6Xy+owWdgI201iyieg1zEdsfKaHPWosv3tGTDhFFpH4=";

  dontNpmBuild = true;

  postPatch = ''
    cp ${gogScript} gog.js
    substituteInPlace gog.js \
      --replace-fail "import { launchContext } from './src/browser.js';" "import { chromium } from 'patchright';" \
      --replace-fail "launchContext(cfg, {" "chromium.launchPersistentContext(cfg.dir.browser, {" \
      --replace-fail "channel: 'chrome'," ""
    substituteInPlace epic-games.js gog.js \
      --replace-fail "launchPersistentContext(cfg.dir.browser, {" \
        "launchPersistentContext(cfg.dir.browser, { executablePath: process.env.FGC_CHROME_PATH,"

    substituteInPlace src/util.js \
      --replace-fail "path.resolve(__dirname, '..', 'data', s)" \
        "path.resolve(process.env.FGC_DATA_DIR || path.resolve(__dirname, '..', 'data'), s)"

    # GOG persists the first error indefinitely unless statuses are updated.
    # Allow later claims or already-owned results to clear stale failures.
    substituteInPlace gog.js \
      --replace-fail "db.data[user][title].status ||= status;" \
        "db.data[user][title].status = status;"

    substituteInPlace epic-games.js gog.js \
      --replace-fail "headless: false," "headless: cfg.headless,"

    # The login prompts run under systemd without a TTY. enquirer's timeout
    # plugin cancels the prompt from a timer callback outside the promise
    # chain that util.js already catches, so the uncaught ERR_USE_AFTER_CLOSE
    # kills the whole run at the login timeout. Swallow that cancellation and
    # let the script fall through to its browser-login wait.
    substituteInPlace src/util.js \
      --replace-fail "      prompt.cancel();" \
        "      try { prompt.cancel(); } catch { }"

    # The first navigation can fail on a transient network condition (seen on
    # pi: net::ERR_NAME_NOT_RESOLVED overnight). Classify it as retryable (75)
    # instead of letting the uncaught error exit 1 and skip the day's retry.
    substituteInPlace epic-games.js \
      --replace-fail "await page.goto(URL_CLAIM, { waitUntil: 'domcontentloaded' }); // 'domcontentloaded' faster than default 'load' https://playwright.dev/docs/api/class-page#page-goto" \
        "try { await page.goto(URL_CLAIM, { waitUntil: 'domcontentloaded' }); } catch (e) { console.error('Epic: navigation failed:', e.message.split('\\n')[0]); process.exit(/TimeoutError|net::ERR/.test(e.name + ' ' + e.message) ? 75 : 1); } // 'domcontentloaded' faster than default 'load' https://playwright.dev/docs/api/class-page#page-goto"
    substituteInPlace gog.js \
      --replace-fail "await page.goto(URL_CLAIM, { waitUntil: 'domcontentloaded' }); // default 'load' takes forever" \
        "try { await page.goto(URL_CLAIM, { waitUntil: 'domcontentloaded' }); } catch (e) { console.error('GOG: navigation failed:', e.message.split('\\n')[0]); process.exit(/TimeoutError|net::ERR/.test(e.name + ' ' + e.message) ? 75 : 1); } // default 'load' takes forever"

    substituteInPlace epic-games.js \
      --replace-fail "console.error('Not signed in anymore. Please login in the browser or here in the terminal.');" \
        "if (cfg.headless) throw new Error('Epic: saved session expired; headed login required.'); console.error('Not signed in anymore. Please login in the browser or here in the terminal.');"
    substituteInPlace gog.js \
      --replace-fail "console.error('Not signed in anymore.');" \
        "if (cfg.headless) throw new Error('GOG: saved session expired; headed login required.'); console.error('Not signed in anymore.');" \
      --replace-fail "console.error('Could not determine GOG login state - page structure changed?');" \
        "throw new Error('GOG: cannot determine saved login state.');"

    substituteInPlace epic-games.js gog.js \
      --replace-fail "process.exitCode ||= 1;" "process.exitCode = 1;"
    substituteInPlace epic-games.js \
      --replace-fail "game.status = 'failed';" \
        "const challenged = (await iframe.locator('#h_captcha_challenge_checkout_free_prod iframe, .payment__errors:has-text(\"Failed to challenge captcha\")').count().catch(() => 1)) > 0; process.exitCode = challenged || e.name !== 'TimeoutError' ? 1 : (process.exitCode || 75); game.status = 'failed';" \
      --replace-fail "console.error('  Got hcaptcha challenge! Lost trust due to too many login attempts? You can solve the captcha in the browser or get a new IP address.');" \
        "process.exitCode = 1; console.error('  Got hcaptcha challenge! Lost trust due to too many login attempts? You can solve the captcha in the browser or get a new IP address.');"

    substituteInPlace gog.js \
      --replace-fail "notify_games.push({ title, url, status });" \
        "const outcome = String(status).toLowerCase(); if (!['claimed', 'existed', 'giveaway has ended'].includes(outcome)) { process.exitCode = ['internal server error', 'service unavailable', 'bad gateway', 'gateway timeout', 'too many requests'].includes(outcome) ? (process.exitCode || 75) : 1; } notify_games.push({ title, url, status });"
  '';

  meta = {
    description = "Automatically claims free games on the Epic Games Store and GOG";
    homepage = "https://github.com/vogler/free-games-claimer";
    license = lib.licenses.agpl3Only;
  };
}
