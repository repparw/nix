{
  pkgs,
  osConfig,
  inputs,
  ...
}: {
  imports = [
    ./tridactyl.nix
  ];

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
        "datareporting.policy.firstRunURL" = "";
        "browser.translations.automaticallyPopup" = false;
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "extensions.autoDisableScopes" = 0;
      };
    };

    profiles = let
      commonProfile = {
        userChrome = builtins.readFile ../../source/userChrome.css;
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
        };
    };
  };
}
