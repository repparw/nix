{
  pkgs,
  lib,
  osConfig,
  config,
  ...
}:
let
  # Override tridactyl to use beta builds
  tridactyl-beta = pkgs.firefox-addons.tridactyl.overrideAttrs (_old: {
    version = "1.24.4pre7258";
    src = pkgs.fetchurl {
      url = "https://tridactyl.cmcaine.co.uk/betas/tridactyl2-1.24.4pre7258.xpi";
      sha256 = "sha256-1h3mghbb4fi4rg30barr40bxj7008vw8jy8026bg2ryj57ljx01z";
    };
  });
in
{
  imports = [
    ./tridactyl.nix
  ];

  config = lib.mkIf osConfig.modules.gui.enable {
    programs = {
      firefox = {
        enable = true;

        configPath = "${config.xdg.configHome}/mozilla/firefox"; # TODO https://github.com/nix-community/home-manager/pull/8672

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
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            "sidebar.verticalTabs" = true;
            "sidebar.visibility" = "expand-on-hover";
            "sidebar.animation.expand-on-hover.duration-ms" = 200;
          };
        };

        profiles =
          let
            commonProfile = {
              userChrome = ''
                #sidebar-button {
                  display: none !important;
                }
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
                  tridactyl-beta
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
                  "addon@darkreader.org".settings = import ./darkreader.nix;
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
            kiosk = commonProfile // {
              id = 1;
              path = "kiosk";
              extensions = with pkgs.firefox-addons; {
                force = true;
                settings = {
                  "sponsorblock@ajay.app".settings = {
                    hideUploadButtonPlayerControls = true;
                    dontShowNotice = true;
                  };
                  "{3c6bf0cc-3ae2-42fb-9993-0d33104fdcaf}".settings = import ./improvedtube.nix;
                };
                packages = [
                  youtube-addon
                  sponsorblock
                  dearrow
                  tampermonkey
                ];
              };
            };
          };
      };
      chromium = {
        enable = true;
        extensions = [
          { id = "lmeddoobegbaiopohmpmmobpnpjifpii"; } # open in firefox
          { id = "ddkjiahejlhfcafbddmgiahcphecmpfh"; } # ublock
        ];
        nativeMessagingHosts = [ pkgs.native-client ];
      };

    };

  };
}
