{
  pkgs,
  lib,
  osConfig,
  config,
  ...
}:
{
  imports = [
    ./tridactyl.nix
  ];

  config = lib.mkIf osConfig.modules.gui.enable {
    programs.firefox = {
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
            extensions = with pkgs.nur.repos.rycee.firefox-addons; {
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
                tridactyl
                ublock-origin
              ];
            };
          };
        in
        {
          default = commonProfile // {
            id = 0;
            path = "default";
            extensions = with pkgs.nur.repos.rycee.firefox-addons; {
              force = true;
              settings = {
                "${darkreader.addonId}".settings = import ./darkreader.nix;
              };
              packages = [
                darkreader
                bitwarden
                refined-github
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
            extensions = with pkgs.nur.repos.rycee.firefox-addons; {
              force = true;
              settings = {
                "${sponsorblock.addonId}".settings = {
                  hideUploadButtonPlayerControls = true;
                  dontShowNotice = true;
                };
                "${improved-tube.addonId}".settings = import ./improvedtube.nix;
              };
              packages = [
                improved-tube
                sponsorblock
                dearrow
                tampermonkey
              ];
            };
          };
        };
    };
  };
}
