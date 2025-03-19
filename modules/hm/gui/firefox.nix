{pkgs, ...}: {
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
      };
    };

    profiles = let
      commonProfile = {
        userChrome = builtins.readFile ../../source/userChrome.css;
        extensions.packages = with pkgs.inputs.firefox-addons; [
          ublock-origin
          tridactyl
          sidebery
        ];
      };
    in {
      default =
        commonProfile
        // {
          id = 0;
          path = "default";
          extensions.packages = with pkgs.inputs.firefox-addons; [
            darkreader
          ];
        };
      kiosk =
        commonProfile
        // {
          id = 1;
          path = "kiosk";
          extensions.packages = with pkgs.inputs.firefox-addons; [
            improved-tube
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
