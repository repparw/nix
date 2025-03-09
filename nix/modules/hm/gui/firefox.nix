{
  pkgs,
  ...
}:
{
  programs.firefox = {
    enable = true;

    nativeMessagingHosts = [ pkgs.tridactyl-native ];

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
        "browser.display.use_document_fonts" = 0;
        "browser.translations.automaticallyPopup" = false;
      };
    };

    profiles = {
      default = {
        id = 0;
        userChrome = (builtins.readFile ../source/userChrome.css);
        path = "default";
        settings = {
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "layers.acceleration.force-enabled" = true;
          "gfx.webrender.all" = true;
          "gfx.webrender.enabled" = true;
          "layout.css.backdrop-filter.enabled" = true;
          "svg.context-properties.content.enabled" = true;
        };
      };
      kiosk = {
        id = 1;
        userChrome = (builtins.readFile ../source/userChrome.css);
        path = "kiosk";
        settings = {
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "layers.acceleration.force-enabled" = true;
          "gfx.webrender.all" = true;
          "gfx.webrender.enabled" = true;
          "layout.css.backdrop-filter.enabled" = true;
          "svg.context-properties.content.enabled" = true;
        };
      };
      socials = {
        id = 2;
        path = "socials";
        userChrome = (builtins.readFile ../source/userChrome.css);
        settings = {
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "layers.acceleration.force-enabled" = true;
          "gfx.webrender.all" = true;
          "gfx.webrender.enabled" = true;
          "layout.css.backdrop-filter.enabled" = true;
          "svg.context-properties.content.enabled" = true;
        };
      };
    };
  };
}
