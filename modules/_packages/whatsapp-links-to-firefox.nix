{ runCommand, writeText }:

# Minimal Manifest V3 extension that sends external links clicked inside the
# WhatsApp web app to Firefox.
#
# Why not the store "Open in Firefox" extension? Its source-aware routing
# (the custom script) is injected as an inline <script> into the page's main
# world, so WhatsApp's enforced `script-src` CSP (nonce, no 'unsafe-inline')
# blocks it. Its remaining automatic mode ("reverse") is global to every
# Helium window, which would also reroute normal browsing. A dedicated
# extension keeps the effect scoped to web.whatsapp.com and, having no stored
# settings, is immune to the extension-state wipes.
#
# It is loaded unpacked via --load-extension (see heliumFlags in browser.nix).
# `key` exists only to pin a stable extension id across rebuilds; the native
# host com.add0n.node checks that exact id in allowed_origins (browser.nix,
# allowed_origins).
let
  manifest = writeText "manifest.json" (
    builtins.toJSON {
      manifest_version = 3;
      name = "WhatsApp links in Firefox";
      description = "Open external links clicked in the WhatsApp web app in Firefox.";
      version = "1.0.0";
      key = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqhg7D4BqbITFlgY69ddzQE5y8LObUKncQOcIelhhQ4z3FaBWwU1Kx//HxpWJvxTf9sYosdg5P2KWOfT1qcziI6QhyCNKuFSeXIl2tZ3hkcHH9j7ajifsnTajvA5EP/N5YBOtptsZfziYCl4kgM4F0jDrruHsDVGfpD8BA5Qu7X5FCDyMyazYQP56xeuPM0HAyTzog8XoMxWjm9ynxLzdTE/rHFon0CxoyXNtHOeK4uk6hT4JcJNPPZXvYHZCOb8e3ZbkmiIDKWMyAq09DwWgAWW04n0NoRoicD0AebTZP5yPN5uzOJKsI0wHIcxvpeSL3BUlHQsb33lcKfZQzrhGMQIDAQAB";
      permissions = [ "nativeMessaging" ];
      background.service_worker = "service-worker.js";
      content_scripts = [
        {
          matches = [ "https://web.whatsapp.com/*" ];
          js = [ "content.js" ];
          run_at = "document_start";
          all_frames = true;
        }
      ];
    }
  );

  content = writeText "content.js" ''
    'use strict';

    // WhatsApp's own hosts stay inside Helium. Everything else that is a plain
    // http(s) link is handed to the background worker, which starts Firefox
    // through the com.add0n.node native host.
    const INTERNAL = /(^|\.)whatsapp\.com$/i;

    document.addEventListener('click', event => {
      if (
        event.button !== 0 ||
        event.altKey || event.ctrlKey || event.metaKey || event.shiftKey
      ) {
        return;
      }

      const anchor = event.target instanceof Element
        ? event.target.closest('a[href]')
        : null;
      if (!anchor) {
        return;
      }

      let url;
      try {
        url = new URL(anchor.href);
      }
      catch (e) {
        return;
      }

      if (url.protocol !== 'http:' && url.protocol !== 'https:') {
        return;
      }
      if (INTERNAL.test(url.hostname)) {
        return;
      }

      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      chrome.runtime.sendMessage({ cmd: 'open-in-firefox', url: url.href });
    }, true);
  '';

  worker = writeText "service-worker.js" ''
    'use strict';

    const NATIVE_HOST = 'com.add0n.node';
    const FIREFOX = 'firefox';

    chrome.runtime.onMessage.addListener(message => {
      if (!message || message.cmd !== 'open-in-firefox' || typeof message.url !== 'string') {
        return;
      }

      chrome.runtime.sendNativeMessage(NATIVE_HOST, {
        cmd: 'exec',
        command: FIREFOX,
        arguments: [ message.url ],
        properties: {}
      }, response => {
        if (chrome.runtime.lastError) {
          console.warn(
            'whatsapp-links-to-firefox: native messaging failed:',
            chrome.runtime.lastError.message
          );
        }
        else if (response && response.code !== 0) {
          console.warn(
            'whatsapp-links-to-firefox: firefox exited',
            response.code,
            response.stderr
          );
        }
      });
    });
  '';
in
runCommand "whatsapp-links-to-firefox-1.0.0"
  {
    passthru.extensionId = "clpjajfpoaelhjkkjkockjbkdjheniik";
  }
  ''
    mkdir -p "$out"
    cp ${manifest} "$out/manifest.json"
    cp ${content} "$out/content.js"
    cp ${worker} "$out/service-worker.js"
  ''
