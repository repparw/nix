{
  den,
  inputs,
  lib,
  ...
}:
let
  heliumExtensionIds = [
    "nngceckbapebfimnlniiiahkandclblb"
    "mnjggcdmjocbbbhaepdhchncahnbgone"
    "enamippconapkdmgfgjchkhakpfinmaj"
    "bnomihfieiccainjcjblhegjgglakjdd"
    "dbepggeogbaibhgnhhndojpepiihcmeb"
    "mfnicocicmmlkpjnaffgihfjhdgjkdjg"
  ];

in
{
  flake-file.inputs.firefox-addons = {
    url = "github:petrkozorezov/firefox-addons-nix";
    inputs.flake-utils.follows = "flake-utils";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake-file.inputs.helium-nix = {
    url = "github:oxcl/nix-flake-helium-browser";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.gui.provides.browser = {
    nixos = { config, ... }: {
      nixpkgs.overlays = [
        inputs.firefox-addons.overlays.default
        (final: prev: {
          firefox-addons = final.lib.mapAttrs (
            name: pkg:
            pkg.overrideAttrs (old: {
              meta = old.meta // {
                license = final.lib.licenses.unfree;
              };
            })
          ) prev.firefox-addons;
        })
      ];

      # Chromium settles policy reloads using file mtimes. Store symlinks keep
      # epoch mtimes and let a directory-enumeration race publish empty policy.
      environment.etc."chromium/policies/managed/helium-nixos.json".mode = "0644";
      environment.etc."chromium/policies/managed/extra.json" =
        lib.mkIf (config.programs.chromium.enable && config.programs.chromium.extraOpts != { })
          {
            mode = "0644";
          };
      environment.etc."chromium/policies/managed/helium-nixos.json".text = builtins.toJSON {
        BrowserSignin = 0;
        PasswordManagerEnabled = false;
        ExtensionSettings = lib.genAttrs heliumExtensionIds (_: {
          installation_mode = "normal_installed";
          # Helium rewrites this Web Store URL to its extension proxy. The
          # Google URL bypasses that rewrite and stalls policy installs.
          update_url = "https://update-url-to-be-replaced.qjz9zk";
        });
      };
    };

    homeManager =
      {
        pkgs,
        config,
        osConfig,
        lib,
        ...
      }:
      let
        ndrop = pkgs.callPackage ../../_packages/ndrop.nix { };
        heliumPackage =
          (inputs.helium-nix.packages.${pkgs.stdenv.hostPlatform.system}.helium.override {
            flags = config.programs.helium.flags;
          }).overrideAttrs
            (old: {
              postInstall = (old.postInstall or "") + ''
                sed -i '/^MimeType=/d' "$out/share/applications/helium.desktop"
              '';
            });

        webThreads = {
          gemini-task = {
            title = "Gemini Task";
            url = "https://gemini.google.com/app?task=";
            aliases = [
              "g"
              "gem"
            ];
          };
          gemini-chat = {
            title = "Gemini Chat";
            url = "https://gemini.google.com/app?q=";
            aliases = [ "gc" ];
          };
          chatgpt = {
            title = "ChatGPT";
            url = "https://chatgpt.com/?q=";
            aliases = [ "gpt" ];
          };
        };

        webThreadsExtension = pkgs.runCommandLocal "vicinae-web-threads-extension" { } ''
          mkdir -p "$out/assets"
          cp ${
            pkgs.writeText "vicinae-web-threads-package.json" (
              builtins.toJSON {
                "$schema" =
                  "https://raw.githubusercontent.com/vicinaehq/vicinae/refs/heads/main/extra/schemas/extension.json";
                name = "web-threads";
                title = "Web Threads";
                description = "Start Gemini and ChatGPT threads in Firefox";
                categories = [ "Productivity" ];
                license = "MIT";
                author = "repparw";
                dependencies."@vicinae/api" = "0.16.8";
                commands = lib.mapAttrsToList (name: thread: {
                  inherit name;
                  title = "New ${thread.title}";
                  description = "Start a new ${thread.title} thread";
                  mode = "no-view";
                  arguments = [
                    {
                      name = "prompt";
                      placeholder = "Prompt";
                      type = "text";
                      required = true;
                    }
                  ];
                }) webThreads;
              }
            )
          } "$out/package.json"
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: thread: ''
              cp ${pkgs.writeText "vicinae-${name}.js" ''
                const { closeMainWindow, showToast, Toast } = require("@vicinae/api");
                const { execFile } = require("node:child_process");
                const { promisify } = require("node:util");

                async function main({ arguments: { prompt } }) {
                  if (!prompt?.trim()) {
                    await showToast({ style: Toast.Style.Failure, title: "Enter a prompt" });
                    return;
                  }

                  try {
                    const url = "${thread.url}" + encodeURIComponent(prompt);
                    await promisify(execFile)("${lib.getExe config.programs.firefox.finalPackage}", ["--new-tab", url]);
                    await closeMainWindow();
                  } catch {
                    await showToast({ style: Toast.Style.Failure, title: "Could not open Firefox" });
                  }
                }

                module.exports = { default: main };
              ''} "$out/${name}.js"
            '') webThreads
          )}
        '';

        hasStylix = config.lib ? stylix;
        readerColors = if hasStylix then config.lib.stylix.colors.withHashtag else null;

        # Simple.css / reader variables mapped onto the base16 palette, per the
        # Stylix style guide: base00 background, base01 alternate background,
        # base02 selection/border, base05 text. The secondary and faint text
        # roles are mixed with base05 below to keep them readable even when
        # base03/base04 are close to the background.
        readerPalette = {
          "--bg" = "base00";
          "--accent-bg" = "base01";
          "--text" = "base05";
          "--border" = "base02";
          "--accent" = "base05";
          "--accent-hover" = "base0E";
          "--code" = "base05";
          "--preformatted" = "base05";
          "--code-bg" = "base01";
          "--code-border" = "base02";
          "--selection" = "base02";
          "--disabled" = "base01";
        };

        # Tridactyl reader theme derived from the Stylix base16 palette. Keeps
        # the Obsidian reader typography (system-ui, 16px, 1.6 line height,
        # 38em measure, heading scale) but takes every color from the scheme
        # configured in modules/aspects/style.nix.
        tridactylReaderCss =
          if readerColors == null then
            null
          else
            ''
              /*
               * Tridactyl reader theme derived from the Stylix palette.
               *
               * Tridactyl injects this file as a <style> element inside the
               * #reader-content iframe, after reader.css and content.css, so
               * these rules override Simple.css.
               */

              :root {
                  color-scheme: dark;

                  --sans-font: system-ui, -apple-system, sans-serif;
                  --mono-font: ui-monospace, "SFMono-Regular", Menlo, Consolas, monospace;
                  --standard-border-radius: 0.6rem;
                  --radius: 0.6rem;

              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (name: base: "    ${name}: ${readerColors.${base}};") readerPalette
              )}

                  /* Keep reader metadata, captions, and list markers readable. */
                  --text-light: color-mix(in srgb, var(--text) 70%, ${readerColors.base04} 30%);
                  --text-muted: var(--text-light);
                  --text-faint: color-mix(in srgb, var(--text) 70%, ${readerColors.base03} 30%);

                  --marked: transparent;

                  --font-size: calc(16px + 0.25vw);
                  --line-height: 1.6;
                  --content-width: 38em;
                  --p-spacing: 1rem;
              }

              html {
                  font-family: var(--sans-font);
              }

              body#tridactyl-reader {
                  background-color: var(--bg);
                  color: var(--text);
                  font-family: var(--sans-font);
                  font-size: var(--font-size);
                  line-height: var(--line-height);
                  text-align: left;
                  hyphens: none;
                  margin: 0;
                  padding: 0;
                  -webkit-font-smoothing: antialiased;
              }

              ::selection {
                  background-color: var(--selection);
              }

              body#tridactyl-reader > header {
                  background-color: transparent;
                  border-bottom: 0;
                  text-align: left;
                  padding: max(4rem, 4vh) 0 0;
                  width: var(--content-width);
                  max-width: calc(100% - 2rem);
                  margin: 0 auto max(2rem, 3vh);
              }

              body#tridactyl-reader > header h1 {
                  font-size: 1.6em;
                  font-weight: 700;
                  letter-spacing: -0.02em;
                  line-height: 1.2;
                  margin: 0 0 0.5em;
                  max-width: none;
                  text-wrap: pretty;
              }

              body#tridactyl-reader > header p {
                  color: var(--text-muted);
                  font-size: 0.9em;
                  line-height: 1.5;
                  margin: 0 0 0.25em;
                  max-width: none;
              }

              body#tridactyl-reader > header p:first-of-type:not(:last-of-type) {
                  color: var(--text);
                  font-weight: 500;
              }

              body#tridactyl-reader > main {
                  width: var(--content-width);
                  max-width: calc(100% - 2rem);
                  margin: 0 auto;
                  padding: 0 0 4rem;
              }

              h1, h2, h3, h4, h5, h6 {
                  color: var(--text);
                  font-weight: 700;
                  text-wrap: pretty;
                  overflow-wrap: break-word;
              }

              h1 { font-size: 1.6em; letter-spacing: -0.02em; line-height: 1.2; margin: 0 0 0.5em; }
              h2 { font-size: 1.3em; letter-spacing: -0.015em; line-height: 1.2; margin: 1.8em 0 0.5em; }
              h3 { font-size: 1.225em; line-height: 1.3; margin: 2em 0 0.5em; }
              h4 { font-size: 1.15em; line-height: 1.4; margin: 2em 0 0; }
              h5 { font-size: 1em; line-height: 1.6; margin: 0 0 1em; }
              h6 { font-size: 1em; line-height: 1.6; text-transform: uppercase; letter-spacing: 0.05em; margin: 0 0 1em; }

              h1 + h2, h2 + h2, h2 + h3, h3 + h4 { margin-top: 0; }

              p { margin: 0 0 var(--p-spacing); }

              a, a:visited { color: var(--accent); text-decoration: underline; }
              a:hover { color: var(--accent-hover); text-decoration: underline; }
              sup a { color: var(--text-muted); text-decoration: none; }

              ol, ul {
                  padding: 0.5rem 0 1rem 0;
                  padding-inline-start: 1em;
                  margin: 0;
                  margin-inline-start: 0.5em;
              }

              ol > li, ul > li { padding: 0.15rem 0; }
              ol > li::marker, ul > li::marker { color: var(--text-faint); }
              ul > li { list-style: disc; }
              ul > li::marker { font-size: 95%; }
              ol > li p, ul > li p { margin-top: 0; margin-bottom: 0; }

              blockquote {
                  margin: var(--p-spacing) 0;
                  padding-inline-start: 1.5rem;
                  border-left: 2px solid var(--text-faint);
                  color: inherit;
                  font-style: normal;
              }

              hr {
                  background-color: var(--border);
                  width: 100%;
                  border: 0;
                  height: 1px;
                  margin: 1.5em 0;
              }

              code, pre, kbd, samp, tt {
                  font-family: var(--mono-font);
                  font-size: 0.8em;
                  color: var(--text);
                  background-color: var(--code-bg);
                  border: 1px solid var(--code-border);
                  border-radius: 4px;
              }

              code, kbd, samp, tt { padding: 0.1em 0.25em; }

              pre {
                  white-space: pre;
                  max-width: 100%;
                  overflow-x: auto;
                  padding: 0.75rem 1rem;
                  margin: var(--p-spacing) 0;
              }

              pre code, pre pre, pre kbd, pre samp, pre tt {
                  font-size: inherit;
                  border: 0;
                  background-color: transparent;
                  padding: 0;
              }

              table {
                  font-size: 0.9em;
                  line-height: calc(var(--line-height) * 0.9);
                  border-collapse: collapse;
                  max-width: 100%;
                  width: auto;
                  margin: 1.5rem 0;
              }

              table tr td, table tr th {
                  padding: 0.25em 0.5em;
                  border: 1px solid var(--border);
                  text-align: left;
              }

              table th { font-weight: 700; background-color: transparent; }
              table tr:nth-child(even) { background-color: transparent; }

              table caption {
                  font-weight: 700;
                  margin-bottom: 0.5rem;
                  color: var(--text);
                  text-align: left;
              }

              img, video { max-width: 100%; height: auto; border-radius: var(--radius); }
              figure { margin: 1em 0; overflow-x: auto; }

              figcaption, caption {
                  color: var(--text-muted);
                  font-size: 85%;
                  line-height: calc(var(--line-height) * 0.9);
                  margin-top: 0.5em;
                  margin-bottom: 1em;
                  text-align: left;
              }

              small[class*="caption"] { color: var(--text-muted); font-size: 85%; }

              mark {
                  color: var(--text);
                  background-color: transparent;
                  padding: 0;
                  border-radius: 0;
              }

              article, section, fieldset { border: 0; border-radius: 0; padding: 0; margin: 0; }

              aside {
                  float: none;
                  width: auto;
                  margin: var(--p-spacing) 0;
                  padding: 0;
                  background-color: transparent;
                  border: 0;
                  border-radius: 0;
                  font-size: inherit;
              }

              details, summary { background-color: transparent; border: 0; padding: 0; margin: 0; }
              summary { font-weight: 700; cursor: pointer; }
            '';
      in
      {
        imports = [ inputs.helium-nix.homeModules.default ];

        home.packages = [
          (pkgs.writers.writePython3Bin "webapp" { flakeIgnore = [ "E501" ]; } ''
            import os
            import sys
            from urllib.parse import urlsplit

            if len(sys.argv) < 3:
                sys.exit("usage: webapp <app-id> <url> [helium args...]")
            app_id, url, *flags = sys.argv[1:]
            parsed = urlsplit(url)
            host = parsed.hostname or ""
            if ":" in host:
                host = f"[{host}]"
            app_name = f"{host}_{parsed.path or '/'}".replace("/", "_").replace(" ", "_")
            chrome_id = f"chrome-{app_name}-Default" if host else app_id
            os.execv("${ndrop}/bin/ndrop", [
                "ndrop", "-F", "-c", chrome_id,
                "${heliumPackage}/bin/helium", f"--app={url}", *flags,
            ])
          '')
        ];

        programs.vicinae.extensions = [ webThreadsExtension ];

        home.file = {
          ".config/tridactyl/web-threads.js".source = ./web-threads.js;
          ".config/tridactyl/themes/stylix.css" = lib.mkIf hasStylix {
            text = tridactylReaderCss;
          };
          ".config/tridactyl/tridactylrc".text = ''
            " General Settings
            set configversion 2.0
            set newtab about:blank
            set markjumpnoisy false
            set modeindicatormodes.ignore false
            set theme midnight
            set editorcmd xdg-terminal-exec -- nvim
            set smoothscroll true
            set tabsort mru

            set searchurls.n https://mynixos.com/search?q=%s
            set searchurls., https://search.nixos.org/packages?channel=unstable&query=%s
            ${lib.concatMapStringsSep "\n" (
              thread:
              lib.concatMapStringsSep "\n" (alias: "set searchurls.${alias} ${thread.url}%s") thread.aliases
            ) (lib.attrValues webThreads)}

            autocmd DocStart ^https://gemini[.]google[.]com/app[?] js -r web-threads.js
            autocmd DocStart ^https://chatgpt[.]com/[?] js -r web-threads.js

            " Binds
            bind ;c hint -c [class*="expand"],[class*="togg"],[class="comment_folder"]

            unbind <F1>
            unbind <C-e>

            bind gd tabdetach

            bind J tabnext --nowrap
            bind K tabprev --nowrap

            bind gr reader

            " Subconfig binds
            bindurl .*.youtube.com/watch yy composite urlmodify_js -Q list | urlmodify_js -Qu index | urlmodify_js -ru .*\.youtube\.com/watch\?v= https://youtu.be/ | clipboard yank
            bindurl www.youtube.com gm urlmodify -t www music

            unbindurl x.com j
            unbindurl x.com k

            " Subconfig Settings
            seturl youtube.com modeindicator false
            ${lib.optionalString (
              osConfig.modules.services.domain or null != null
            ) "seturl jellyfin.${osConfig.modules.services.domain} modeindicator false"}

            " Reader theme (must run after the seturl lines above: colourscheme's
            " seturl is shimmed to the active tab's content script, which is only
            " guaranteed to be loaded by the end of the rc).
            colourscheme --module=reader stylix
          '';
        };
        programs = {
          firefox = {
            enable = true;
            nativeMessagingHosts = [ pkgs.tridactyl-native ];

            policies = {
              CaptivePortal = false;
              DisableAppUpdate = true;
              DisableFirefoxStudies = true;
              DisablePocket = true;
              DisableProfileImport = true;
              DisableTelemetry = true;
              HardwareAcceleration = true;
              NoDefaultBookmarks = true;
              OverrideFirstRunPage = "";
              OverridePostUpdatePage = "";
              PasswordManagerEnabled = false;
              OfferToSaveLogins = false;
              OfferToSaveLoginsDefault = false;
              Preferences = {
                "browser.translations.automaticallyPopup" = false;
                "datareporting.policy.firstRunURL" = "";
                "extensions.autoDisableScopes" = 0;
                "network.trr.mode" = 5;
                "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
                "sidebar.verticalTabs" = true;
                "sidebar.visibility" = "expand-on-hover";
                "sidebar.animation.expand-on-hover.delay-duration-ms" = 0;
                "sidebar.animation.expand-on-hover.duration-ms" = 0;
              };
            };

            profiles =
              let
                commonProfile = {
                  userChrome = ''
                    #sidebar-button { display: none !important; }
                  '';
                  extensions = with pkgs.firefox-addons; {
                    force = true;
                    settings = {
                      "${ublock-origin.addonId}".settings = {
                        "selectedFilterLists" = [
                          "user-filters"
                          "ublock-filters"
                          "ublock-badware"
                          "ublock-privacy"
                          "ublock-quick-fixes"
                          "ublock-unbreak"
                          "easylist"
                          "easyprivacy"
                          "urlhaus-1"
                          "plowe-0"
                          "adguard-other-annoyances"
                          "adguard-popup-overlays"
                          "adguard-widgets"
                        ];
                        "whitelist" = [
                          "chrome-extension-scheme"
                          "meet.google.com"
                          "moz-extension-scheme"
                        ];
                      };
                    };
                    packages = [
                      tridactyl-vim
                      ublock-origin
                    ];
                  };
                };
              in
              {
                default = commonProfile // {
                  id = 0;
                  path = "default";
                  extensions = with pkgs.firefox-addons; {
                    force = true;
                    settings = {
                      "addon@darkreader.org".settings = {
                        schemeVersion = 0;
                        enabled = true;
                        fetchNews = true;
                        theme = {
                          mode = 1;
                          brightness = 100;
                          contrast = 100;
                          grayscale = 0;
                          sepia = 0;
                          useFont = false;
                          textStroke = 0;
                          engine = "dynamicTheme";
                          darkSchemeBackgroundColor = "#181a1b";
                          darkSchemeTextColor = "#e8e6e3";
                          lightSchemeBackgroundColor = "#dcdad7";
                          lightSchemeTextColor = "#181a1b";
                          scrollbarColor = "";
                          selectionColor = "auto";
                          styleSystemControls = false;
                          lightColorScheme = "Default";
                          darkColorScheme = "Default";
                          immediateModify = false;
                        };
                        presets = [ ];
                        customThemes = [ ];
                        enabledByDefault = true;
                        enabledFor = [ ];
                        disabledFor = [ ];
                        changeBrowserTheme = false;
                        syncSettings = true;
                        syncSitesFixes = true;
                        automation.enabled = false;
                        previewNewDesign = true;
                        previewNewestDesign = false;
                        enableForPDF = true;
                        enableForProtectedPages = false;
                        enableContextMenus = false;
                        detectDarkTheme = true;
                        notifyOfNews = false;
                      };
                    };
                    packages = [
                      darkreader
                      bitwarden-password-manager
                      refined-github-
                      raindropio
                    ];
                  };
                  search = {
                    force = true;
                    engines =
                      (lib.mapAttrs' (
                        _: thread:
                        lib.nameValuePair thread.title {
                          urls = [ { template = thread.url + "{searchTerms}"; } ];
                          definedAliases = thread.aliases;
                        }
                      ) webThreads)
                      // {
                        "Nix options" = {
                          urls = [ { template = "https://mynixos.com/search?q={searchTerms}"; } ];
                          definedAliases = [ "n" ];
                        };
                        "Nixpkgs" = {
                          urls = [ { template = "https://search.nixos.org/packages?channel=unstable&query={searchTerms}"; } ];
                          definedAliases = [
                            "np"
                            ","
                          ];
                        };
                        "IMDb" = {
                          urls = [ { template = "https://www.imdb.com/find?q={searchTerms}&s=all"; } ];
                          definedAliases = [ "imdb" ];
                        };
                        "youtube" = {
                          urls = [ { template = "https://www.youtube.com/results?search_query={searchTerms}"; } ];
                          definedAliases = [ "y" ];
                        };
                        "GitHub" = {
                          urls = [ { template = "https://github.com/search?q={searchTerms}"; } ];
                          definedAliases = [ "gh" ];
                        };
                      };
                    default = "google";
                  };
                };
              };
          };

          helium = {
            enable = true;
            package = heliumPackage;
            flags = [
              "--ozone-platform-hint=auto"
              "--force-renderer-accessibility"
              "--silent-debugger-extension-api"
              "--password-store=basic"
            ];
          };
        };
      };
  };
}
