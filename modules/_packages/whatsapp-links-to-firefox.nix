{ runCommand, writeText }:

# The store extension's per-site script is blocked by WhatsApp's CSP; its
# automatic routing affects all sites. This stateless extension is site-scoped.
# The manifest key pins the ID allowed by the native host in browser.nix.
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
    document.addEventListener('click', event => {
      if (event.button !== 0 || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
      const anchor = event.target instanceof Element ? event.target.closest('a[href]') : null;
      if (!anchor) return;
      const url = new URL(anchor.href);
      if (!['http:', 'https:'].includes(url.protocol) || /(^|\.)whatsapp\.com$/i.test(url.hostname)) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      chrome.runtime.sendMessage({url: url.href});
    }, true);
  '';

  worker = writeText "service-worker.js" ''
    chrome.runtime.onMessage.addListener(message => {
      if (typeof message?.url !== 'string') return;
      chrome.runtime.sendNativeMessage('com.add0n.node', {
        cmd: 'exec', command: 'firefox', arguments: [message.url], properties: {}
      }).then(response => {
        if (response?.code) console.warn('Firefox failed:', response.stderr);
      }).catch(error => console.warn('Firefox native messaging failed:', error));
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
