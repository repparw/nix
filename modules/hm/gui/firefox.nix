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
          userChrome = ../../source/userChrome.css;
          extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
            ublock-origin
            sidebery
            tridactyl
          ];
        };
      in {
        default =
          commonProfile
          // {
            id = 0;
            path = "default";
            extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
              darkreader
              bitwarden
              refined-github
            ];
          };
        kiosk =
          commonProfile
          // {
            id = 1;
            path = "kiosk";
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
            #userContent = ''
            #  @-moz-document domain("web.whatsapp.com") {
            #    #app > div > div:last-child > div:first-child {
            #      max-width: initial !important;
            #      width: 100% !important;
            #      height: 100% !important;
            #      margin: 0 !important;
            #      position: unset !important;
            #    }
            #  }
            #'';
          };
      };
    };
  };
}
