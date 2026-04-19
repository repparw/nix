{
  den,
  inputs,
  pkgs,
  lib,
  ...
}:
{
  flake-file.inputs.firefox-addons = {
    url = "github:petrkozorezov/firefox-addons-nix";
    inputs.flake-utils.follows = "flake-utils";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.gui.provides.browser = {
    homeManager =
      {
        pkgs,
        config,
        osConfig,
        ...
      }:
      {
        home.file.".config/tridactyl/tridactylrc".text = ''
          " General Settings
          set configversion 2.0
          set newtab about:blank
          set markjumpnoisy false
          set modeindicatormodes.ignore false
          set theme midnight
          set editorcmd foot nvim
          set smoothscroll true
          set tabsort mru

          set searchurls.n https://mynixos.com/search?q=%s
          set searchurls., https://search.nixos.org/packages?channel=unstable&query=%s

          " Binds
          bind ;c hint -c [class*="expand"],[class*="togg"],[class="comment_folder"]

          unbind <F1>
          unbind <C-e>

          bind gd tabdetach

          bind yy clipboard yankshort

          bind J tabnext --nowrap
          bind K tabprev --nowrap

          bind gr reader

          " Subconfig binds
          bindurl .*.youtube.com yy composite urlmodify_js -Q list | urlmodify_js -ru .*\.youtube\.com/watch\?v= https://youtu.be/ | clipboard yank
          bindurl www.youtube.com gm urlmodify -t www music

          unbindurl x.com j
          unbindurl x.com k

          " Subconfig Settings
          seturl youtube.com modeindicator false
          ${lib.optionalString (
            osConfig.modules.services.domain or null != null
          ) "seturl jellyfin.${osConfig.modules.services.domain} modeindicator false"}

          autocmd DocStart tradingview.com mode ignore
        '';
        programs = {
          firefox = {
            enable = true;
            configPath = "${config.xdg.configHome}/mozilla/firefox";
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
                "network.trr.mode" = 5;
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
                    #sidebar-button { display: none !important; }
                  '';
                  extensions = with pkgs.firefox-addons; {
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
                      tridactyl-vim
                      ublock-origin
                    ];
                  };
                };
              in
              {
                default = commonProfile // {
                  id = 0;
                  path = "default";
                  extensions = with pkgs.firefox-addons; {
                    force = true;
                    settings = {
                      "addon@darkreader.org".settings = {
                        schemeVersion = 0;
                        enabled = true;
                        fetchNews = true;
                        theme = {
                          mode = 1;
                          brightness = 100;
                          contrast = 100;
                          grayscale = 0;
                          sepia = 0;
                          useFont = false;
                          textStroke = 0;
                          engine = "dynamicTheme";
                          darkSchemeBackgroundColor = "#181a1b";
                          darkSchemeTextColor = "#e8e6e3";
                          lightSchemeBackgroundColor = "#dcdad7";
                          lightSchemeTextColor = "#181a1b";
                          scrollbarColor = "";
                          selectionColor = "auto";
                          styleSystemControls = false;
                          lightColorScheme = "Default";
                          darkColorScheme = "Default";
                          immediateModify = false;
                        };
                        presets = [ ];
                        customThemes = [ ];
                        enabledByDefault = true;
                        enabledFor = [ ];
                        disabledFor = [ ];
                        changeBrowserTheme = false;
                        syncSettings = true;
                        syncSitesFixes = true;
                        automation.enabled = false;
                        previewNewDesign = true;
                        previewNewestDesign = false;
                        enableForPDF = true;
                        enableForProtectedPages = false;
                        enableContextMenus = false;
                        detectDarkTheme = true;
                        notifyOfNews = false;
                      };
                    };
                    packages = [
                      darkreader
                      bitwarden-password-manager
                      refined-github-
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
                  extensions = with pkgs.firefox-addons; {
                    force = true;
                    settings = {
                      "sponsorblock@ajay.app".settings = {
                        hideUploadButtonPlayerControls = true;
                        dontShowNotice = true;
                      };
                      "{3c6bf0cc-3ae2-42fb-9993-0d33104fdcaf}".settings = {
                        "below_player_loop" = false;
                        "below_player_pip" = false;
                        "below_player_screenshot" = false;
                        "channel_default_tab" = "/videos";
                        "hide_clip_button" = "hidden";
                        "hide_report_button" = true;
                        "hide_shorts_remixing" = true;
                        "hide_voice_search_button" = true;
                        "join" = "hidden";
                        "only_one_player_instance_playing" = true;
                        "player_autofullscreen" = true;
                        "player_forced_playback_speed" = true;
                        "player_playback_speed" = 1.4;
                        "remove_history_shorts" = true;
                        "remove_home_page_shorts" = true;
                        "remove_member_only" = true;
                        "remove_shorts_reel_search_results" = true;
                        "remove_subscriptions_shorts" = true;
                        "remove_trending_shorts" = true;
                        "theme" = "dark";
                        "track_watched_videos" = false;
                        "transcript" = false;
                        "youtube_home_page" = "/feed/subscriptions";
                      };
                    };
                    packages = [
                      youtube-addon
                      sponsorblock
                      dearrow
                      tampermonkey
                    ];
                  };
                };
              };
          };

          chromium = {
            enable = true;
            extensions = [
              { id = "ddkjiahejlhfcafbddmgiahcphecmpfh"; }
            ];
          };
        };
      };
  };
}
