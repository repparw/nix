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
        extensions = with inputs.firefox-addons.packages.${osConfig.system}.pkgs; [
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
          extensions = with inputs.firefox-addons.packages.${osConfig.system}.pkgs; [
            darkreader
            bitwarden
          ];
        };
      kiosk =
        commonProfile
        // {
          id = 1;
          path = "kiosk";
          extensions = with inputs.firefox-addons.packages.${osConfig.system}.pkgs; [
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
