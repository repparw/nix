{
  pkgs,
  lib,
  config,
  ...
}: {
  imports = [
    ./tridactyl.nix
  ];

  config = lib.mkIf config.modules.gui.enable {
    programs.firefox = {
      enable = true;

      nativeMessagingHosts = [pkgs.tridactyl-native];

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

      profiles = let
        commonProfile = {
          # TODO extensions.settings
          extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
            ublock-origin
            tridactyl
          ];
        };
      in {
        default =
          commonProfile
          // {
            id = 0;
            path = "default";
            userChrome = ../../source/userChrome.css;
            extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
              sidebery
              darkreader
              bitwarden
              refined-github
            ];
            search = {
              engines = {
                "Nix options" = {
                  urls = [{template = "https://mynixos.com/search?q={searchTerms}";}];
                  definedAliases = ["n"];
                };
                "Nixpkgs" = {
                  urls = [{template = "https://search.nixos.org/packages?channel=unstable&query={searchTerms}";}];
                  definedAliases = ["np"];
                };
                "IMDb" = {
                  urls = [{template = "https://www.imdb.com/find?q={searchTerms}&s=all";}];
                  definedAliases = ["imdb"];
                };
                "AI" = {
                  urls = [{template = "https://www.t3.chat/new?q={searchTerms}";}];
                  definedAliases = ["ai"];
                };
                "youtube" = {
                  urls = [{template = "https://www.youtube.com/results?search_query={searchTerms}";}];
                  definedAliases = ["y"];
                };
                "GitHub" = {
                  urls = [{template = "https://github.com/search?q={searchTerms}";}];
                  definedAliases = ["gh"];
                };
              };
              default = "google";
            };
          };
        kiosk =
          commonProfile
          // {
            id = 1;
            path = "kiosk";
            userChrome = ''
              .tools-and-extensions.actions-list {
                display: none !important;
              }
            '';
            extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
              improved-tube
              sponsorblock
              dearrow
              tampermonkey
            ];
          };
        socials =
          commonProfile
          // {
            id = 2;
            path = "socials";
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
