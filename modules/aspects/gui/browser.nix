{
  den,
  inputs,
  pkgs,
  lib,
  ...
}:
let
  openInFirefoxExtensionId = "lmeddoobegbaiopohmpmmobpnpjifpii";
in
{
  flake-file.inputs.firefox-addons = {
    url = "github:petrkozorezov/firefox-addons-nix";
    inputs.flake-utils.follows = "flake-utils";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.gui.provides.browser = {
    nixos = {
      environment.etc."chromium/policies/managed/open-in-firefox.json".text = builtins.toJSON {
        "3rdparty".extensions.${openInFirefoxExtensionId} = {
          faqs = false;
          hosts = [
            "app.solidtime.io"
            "music.youtube.com"
            "web.whatsapp.com"
            "www.youtube.com"
            "youtube.com"
          ];
          reverse = true;
        };
      };

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
        chromiumWithoutMimeApps =
          chromium:
          (pkgs.symlinkJoin {
            name = "${chromium.name}-without-mimeapps";
            paths = [ chromium ];
            postBuild = ''
              rm -rf "$out/share/applications"
              install -Dm644 ${chromium}/share/applications/chromium-browser.desktop \
                "$out/share/applications/chromium-browser.desktop"
              sed -i '/^MimeType=/d' "$out/share/applications/chromium-browser.desktop"
            '';
            inherit (chromium) meta;
          })
          // {
            override = args: chromiumWithoutMimeApps (chromium.override args);
          };

        openInFirefoxNativeClient = pkgs.stdenvNoCC.mkDerivation {
          pname = "open-in-firefox-native-client";
          version = "1.0.8";

          src = pkgs.fetchFromGitHub {
            owner = "andy-portmen";
            repo = "native-client";
            rev = "ddcf08fd892319bb5013f46929669273234685ef";
            hash = "sha256-/Zr5FSfZ5Sh1kE/x0wF0Uljg0mnE0QkO6etgopaIXmo=";
          };

          dontBuild = true;

          installPhase = ''
            runHook preInstall

            install -Dm644 host.js "$out/lib/com.add0n.node/host.js"
            install -Dm644 messaging.js "$out/lib/com.add0n.node/messaging.js"

            mkdir -p "$out/bin" "$out/etc/chromium/native-messaging-hosts"
            cat > "$out/bin/com.add0n.node" <<EOF
            #!${pkgs.runtimeShell}
            exec ${lib.getExe pkgs.nodejs} "$out/lib/com.add0n.node/host.js"
            EOF
            chmod +x "$out/bin/com.add0n.node"

            cat > "$out/etc/chromium/native-messaging-hosts/com.add0n.node.json" <<EOF
            {
              "name": "com.add0n.node",
              "description": "Node Host for Native Messaging",
              "path": "$out/bin/com.add0n.node",
              "type": "stdio",
              "allowed_origins": [
                "chrome-extension://${openInFirefoxExtensionId}/"
              ]
            }
            EOF

            runHook postInstall
          '';
        };
      in
      {
        home.file.".config/tridactyl/tridactylrc".text = ''
          " General Settings
          set configversion 2.0
          set newtab about:blank
          set markjumpnoisy false
          set modeindicatormodes.ignore false
          set theme midnight
          set editorcmd foot nvim
          set smoothscroll true
          set tabsort mru

          set searchurls.n https://mynixos.com/search?q=%s
          set searchurls., https://search.nixos.org/packages?channel=unstable&query=%s

          " Binds
          bind ;c hint -c [class*="expand"],[class*="togg"],[class="comment_folder"]

          unbind <F1>
          unbind <C-e>

          bind gd tabdetach

          bind yy clipboard yankshort

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

          autocmd DocStart tradingview.com mode ignore
        '';
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
                    engines = {
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
                      "AI" = {
                        urls = [ { template = "https://chat.repparw.com/?q={searchTerms}"; } ];
                        definedAliases = [ "ai" ];
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

          chromium = {
            enable = true;
            package = chromiumWithoutMimeApps pkgs.chromium;
            commandLineArgs = [ "--password-store=basic" ];
            nativeMessagingHosts = [ openInFirefoxNativeClient ];
            extensions = [
              { id = openInFirefoxExtensionId; }
              { id = "ddkjiahejlhfcafbddmgiahcphecmpfh"; }
              { id = "mnjggcdmjocbbbhaepdhchncahnbgone"; }
              { id = "enamippconapkdmgfgjchkhakpfinmaj"; }
              { id = "bnomihfieiccainjcjblhegjgglakjdd"; }
              { id = "dbepggeogbaibhgnhhndojpepiihcmeb"; }
            ];
          };
        };
      };
  };
}
