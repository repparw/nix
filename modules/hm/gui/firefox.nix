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
      NoDefaultBookmarks = true;
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      Preferences = {
        "datareporting.policy.firstRunURL" = "";
        "browser.translations.automaticallyPopup" = false;
      };
    };

    profiles = let
      commonSettings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "layers.acceleration.force-enabled" = true;
        "gfx.webrender.all" = true;
        "gfx.webrender.enabled" = true;
        "layout.css.backdrop-filter.enabled" = true;
        "svg.context-properties.content.enabled" = true;
      };
      commonProfile = {
        userChrome = builtins.readFile ../../source/userChrome.css;
        settings = commonSettings;
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
