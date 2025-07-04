{
  pkgs,
  lib,
  osConfig,
  ...
}:
{
  imports = [
    ./tridactyl.nix
  ];

  config = lib.mkIf osConfig.modules.gui.enable {
    programs.firefox = {
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
          "media.eme.enabled" = true;
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        };
      };

      profiles =
        let
          commonProfile = {
            extensions = {
              settings = {
                "uBlock0@raymondhill.net".settings = {
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
              # "tridactyl.vim@cmcaine.co.uk".settings = import ./tridactyl.nix;

              packages = with pkgs.nur.repos.rycee.firefox-addons; [
                ublock-origin
                tridactyl
              ];
            };
          };
        in
        {
          default = commonProfile // {
            id = 0;
            path = "default";
            userChrome = ./userChrome.css;
            extensions = {
              force = true;
              settings = {
                "addon@darkreader.org".settings = import ./darkreader.nix;
                # "jid1-xUfzOsOFlzSOXg@jetpack".settings = { # RES }; check format
                "{3c6bf0cc-3ae2-42fb-9993-0d33104fdcaf}".settings = import ./improvedtube.nix;
              };
              packages = with pkgs.nur.repos.rycee.firefox-addons; [
                sidebery
                darkreader
                bitwarden
                refined-github
                reddit-enhancement-suite
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
                  urls = [ { template = "https://www.t3.chat/new?q={searchTerms}"; } ];
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
            userChrome = ''
              .tools-and-extensions.actions-list {
                display: none !important;
              }
            '';
            extensions = {
              force = true;
              settings = {
                "sponsorBlocker@ajay.app".settings = {
                  hideUploadButtonPlayerControls = true;
                };
                "{3c6bf0cc-3ae2-42fb-9993-0d33104fdcaf}".settings = import ./improvedtube.nix;
              };
              packages = with pkgs.nur.repos.rycee.firefox-addons; [
                improved-tube
                sponsorblock
                dearrow
                tampermonkey
              ];
            };
          };
          socials = commonProfile // {
            id = 2;
            path = "socials";
            extensions.force = true;
            userChrome = ''
              .tools-and-extensions.actions-list {
                display: none !important;
              }
            '';
          };
        };
    };
  };
}
