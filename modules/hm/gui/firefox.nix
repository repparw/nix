{pkgs, ...}: {
  imports = [
    ./tridactyl.nix
  ];

  programs.firefox = {
    enable = true;

    nativeMessagingHosts = [pkgs.tridactyl-native];

    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DisableProfileImport = true;
      HardwareAcceleration = true;
      NoDefaultBookmarks = true;
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      CaptivePortal = false;
      Preferences = {
        "datareporting.policy.firstRunURL" = "";
        "browser.translations.automaticallyPopup" = false;
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };
    };

    profiles = let
      commonProfile = {
        userChrome = builtins.readFile ../../source/userChrome.css;
      };
    in {
      default =
        commonProfile
        // {
          id = 0;
          path = "default";
        };
      kiosk =
        commonProfile
        // {
          id = 1;
          path = "kiosk";
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
