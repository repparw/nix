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

  flake-file.inputs.helium-nix = {
    url = "github:penal-colony/helium-nix";
  };

  flake-file.nixConfig = {
    extra-substituters = [ "https://helium-nix.cachix.org" ];
    extra-trusted-public-keys = [
      "helium-nix.cachix.org-1:a8YPjt9O4GPyX0u3gjg/aWpb14teU9aRiSG/MOaSFgw="
    ];
  };

  den.aspects.gui.provides.browser = {
    nixos = {
      imports = [ inputs.helium-nix.nixosModules.helium ];

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
        browserWithoutMimeApps =
          desktopFile: browser:
          (pkgs.symlinkJoin {
            name = "${browser.name}-without-mimeapps";
            paths = [ browser ];
            postBuild = ''
              rm -rf "$out/share/applications"
              install -Dm644 ${browser}/share/applications/${desktopFile} \
                "$out/share/applications/${desktopFile}"
              sed -i '/^MimeType=/d' "$out/share/applications/${desktopFile}"
            '';
            inherit (browser) meta;
          })
          // {
            override = args: browserWithoutMimeApps desktopFile (browser.override args);
          };

        chromiumWithoutMimeApps = browserWithoutMimeApps "chromium-browser.desktop";
        heliumWithoutMimeApps = browserWithoutMimeApps "helium.desktop";
        helium = inputs.helium-nix.packages.${pkgs.stdenv.hostPlatform.system}.helium;
      in
      {
        imports = [ inputs.helium-nix.homeManagerModules.helium ];

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
            extensions = [
              { id = openInFirefoxExtensionId; }
              { id = "ddkjiahejlhfcafbddmgiahcphecmpfh"; }
              { id = "mnjggcdmjocbbbhaepdhchncahnbgone"; }
              { id = "enamippconapkdmgfgjchkhakpfinmaj"; }
              { id = "bnomihfieiccainjcjblhegjgglakjdd"; }
              { id = "dbepggeogbaibhgnhhndojpepiihcmeb"; }
            ];
          };

          helium = {
            enable = true;
            package = heliumWithoutMimeApps helium;
            defaultBrowser = false;
            extraPolicies = {
              BrowserSignin = 0;
              PasswordManagerEnabled = false;
            };
          };
        };
      };
  };
}
