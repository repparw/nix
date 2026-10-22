{
  den,
  inputs,
  lib,
  ...
}:
let
  openInFirefoxId = "lmeddoobegbaiopohmpmmobpnpjifpii";

  heliumExtensionIds = [
    openInFirefoxId
    "nngceckbapebfimnlniiiahkandclblb"
    "mnjggcdmjocbbbhaepdhchncahnbgone"
    "enamippconapkdmgfgjchkhakpfinmaj"
    "bnomihfieiccainjcjblhegjgglakjdd"
    "dbepggeogbaibhgnhhndojpepiihcmeb"
  ];

in
{
  flake-file.inputs.firefox-addons = {
    url = "github:petrkozorezov/firefox-addons-nix";
    inputs.flake-utils.follows = "flake-utils";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake-file.inputs.helium-nix = {
    url = "github:oxcl/nix-flake-helium-browser";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.gui.provides.browser = {
    nixos =
      { config, pkgs, ... }:
      let
        # Helium reads platform policies from /etc/chromium (verified via
        # --enable-logging --v=1: config_dir_policy_loader scans
        # /etc/chromium/policies/managed). The /etc/helium path is not read.
        heliumPolicy = builtins.toJSON {
          BrowserSignin = 0;
          PasswordManagerEnabled = false;
          ExtensionSettings = lib.genAttrs heliumExtensionIds (_: {
            installation_mode = "normal_installed";
            # Helium rewrites this Web Store URL to its extension proxy. The
            # Google URL bypasses that rewrite and stalls policy installs.
            update_url = "https://update-url-to-be-replaced.qjz9zk";
          });
        };
        # Chromium watches the whole managed-policy directory and re-installs
        # every policy-managed extension on reload, which deletes their
        # chrome.storage.local. setup-etc.pl re-creates environment.etc
        # symlinks on every activation, so keep these files out of
        # environment.etc and rewrite them only when the bytes change.
        policyFiles = {
          "helium-nixos.json" = heliumPolicy;
        }
        // lib.optionalAttrs (config.programs.chromium.extraOpts != { }) {
          "extra.json" = builtins.toJSON config.programs.chromium.extraOpts;
        };
      in
      {
        nixpkgs.overlays = [
          inputs.firefox-addons.overlays.default
          (final: prev: {
            firefox-addons = final.lib.mapAttrs (
              name: pkg:
              pkg.overrideAttrs (old: {
                meta = old.meta // {
                  license = final.lib.licenses.unfree;
                };
              })
            ) prev.firefox-addons;
          })
        ];

        environment.etc = lib.mkIf (config.programs.chromium.extraOpts != { }) {
          # programs.chromium regenerates this on every activation; disable the
          # etc entry so the activation script below can keep it stable.
          "chromium/policies/managed/extra.json".enable = lib.mkForce false;
        };

        system.activationScripts.heliumPolicy = {
          deps = [ "etc" ];
          text = ''
            install -d -m 0755 /etc/chromium/policies/managed
          ''
          + lib.concatStrings (
            lib.mapAttrsToList (
              name: content:
              let
                src = pkgs.writeText "chromium-policy-${name}" content;
              in
              ''
                if ! cmp -s ${src} "/etc/chromium/policies/managed/${name}"; then
                  install -m 0644 ${src} "/etc/chromium/policies/managed/${name}"
                fi
              ''
            ) policyFiles
          );
        };
      };

    homeManager =
      {
        pkgs,
        config,
        osConfig,
        lib,
        ...
      }:
      let
        openInNativeHost = pkgs.callPackage ../../_packages/com-addon-node.nix { };
        ndrop = pkgs.callPackage ../../_packages/ndrop.nix { };
        whatsappLinksToFirefox = pkgs.callPackage ../../_packages/whatsapp-links-to-firefox.nix { };
        heliumBase = inputs.helium-nix.packages.${pkgs.stdenv.hostPlatform.system}.helium;
        snapshot = pkgs.writeShellApplication {
          name = "helium-snapshot";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.findutils
          ];
          text = ''
            # Preserve extension storage before version changes (Helium #1978).
            snapshotRoot="''${XDG_STATE_HOME:-$HOME/.local/state}/helium-extension-snapshots"
            marker="$snapshotRoot/launched-version"
            defaultDir="$HOME/.config/net.imput.helium/Default"
            if [ "$(cat "$marker" 2>/dev/null)" != "${heliumBase.name}" ]; then
              dest="$snapshotRoot/pre-${heliumBase.name}"
              if [ ! -d "$dest" ]; then
                mkdir -p "$dest"
                for dir in "Local Extension Settings" "Sync Extension Settings"; do
                  if [ -d "$defaultDir/$dir" ]; then
                    cp -a "$defaultDir/$dir" "$dest/"
                  fi
                done
              fi
              find "$snapshotRoot" -maxdepth 1 -name 'pre-*' -type d | sort -r | tail -n +4 | xargs -r rm -rf
              printf '%s' "${heliumBase.name}" > "$marker"
            fi
          '';
        };
        heliumPackage =
          (heliumBase.override { flags = config.programs.helium.flags; }).overrideAttrs
            (old: {
              nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.makeShellWrapper ];
              postFixup = (old.postFixup or "") + ''
                wrapProgramShell "$out/bin/helium" --run ${snapshot}/bin/helium-snapshot
                sed -i '/^MimeType=/d' "$out/share/applications/helium.desktop"
              '';
            });
        heliumFlags = [
          # Upstream's wrapper does not expand NIXOS_OZONE_WL.
          "--ozone-platform-hint=auto"
          "--force-renderer-accessibility"
          "--silent-debugger-extension-api"
          # All windows share a profile and must use the same encryption backend.
          "--password-store=basic"
          "--load-extension=${whatsappLinksToFirefox}"
        ];
        heliumConfigDir = ".config/net.imput.helium";
      in
      {
        imports = [ inputs.helium-nix.homeModules.default ];

        home.packages = [
          (pkgs.writers.writePython3Bin "webapp" { flakeIgnore = [ "E501" ]; } ''
            import os
            import sys
            from urllib.parse import urlsplit

            if len(sys.argv) < 3:
                sys.exit("usage: webapp <app-id> <url> [helium args...]")
            app_id, url, *flags = sys.argv[1:]
            parsed = urlsplit(url)
            host = parsed.hostname or ""
            if ":" in host:
                host = f"[{host}]"
            # Native Wayland ignores --class. Match Chromium's derived app ID.
            app_name = f"{host}_{parsed.path or '/'}".replace("/", "_").replace(" ", "_")
            chrome_id = f"chrome-{app_name}-Default" if host else app_id
            os.execv("${ndrop}/bin/ndrop", [
                "ndrop", "-F", "-c", chrome_id,
                "${heliumPackage}/bin/helium", f"--app={url}", *flags,
            ])
          '')
        ];

        home.file = {
          ".config/com.add0n.node".source = "${openInNativeHost}/lib/com.add0n.node";
          "${heliumConfigDir}/NativeMessagingHosts/com.add0n.node.json".text = builtins.toJSON {
            name = "com.add0n.node";
            description = "Node Host for Native Messaging";
            path = "${openInNativeHost}/lib/com.add0n.node/run.sh";
            type = "stdio";
            allowed_origins = map (id: "chrome-extension://${id}/") [
              openInFirefoxId
              whatsappLinksToFirefox.extensionId
            ];
          };
          ".config/tridactyl/tridactylrc".text = ''
            " General Settings
            set configversion 2.0
            set newtab about:blank
            set markjumpnoisy false
            set modeindicatormodes.ignore false
            set theme midnight
            set editorcmd xdg-terminal-exec -- nvim
            set smoothscroll true
            set tabsort mru

            set searchurls.n https://mynixos.com/search?q=%s
            set searchurls., https://search.nixos.org/packages?channel=unstable&query=%s

            " Binds
            bind ;c hint -c [class*="expand"],[class*="togg"],[class="comment_folder"]

            unbind <F1>
            unbind <C-e>

            bind gd tabdetach

            bind J tabnext --nowrap
            bind K tabprev --nowrap

            bind gr reader

            " Subconfig binds
            bindurl .*.youtube.com/watch yy composite urlmodify_js -Q list | urlmodify_js -Qu index | urlmodify_js -ru .*\.youtube\.com/watch\?v= https://youtu.be/ | clipboard yank
            bindurl www.youtube.com gm urlmodify -t www music

            unbindurl x.com j
            unbindurl x.com k

            " Subconfig Settings
            seturl youtube.com modeindicator false
            ${lib.optionalString (
              osConfig.modules.services.domain or null != null
            ) "seturl jellyfin.${osConfig.modules.services.domain} modeindicator false"}
          '';
        };
        programs = {
          firefox = {
            enable = true;
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
              PasswordManagerEnabled = false;
              OfferToSaveLogins = false;
              OfferToSaveLoginsDefault = false;
              Preferences = {
                "browser.translations.automaticallyPopup" = false;
                "datareporting.policy.firstRunURL" = "";
                "extensions.autoDisableScopes" = 0;
                "network.trr.mode" = 5;
                "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
                "sidebar.verticalTabs" = true;
                "sidebar.visibility" = "expand-on-hover";
                "sidebar.animation.expand-on-hover.delay-duration-ms" = 0;
                "sidebar.animation.expand-on-hover.duration-ms" = 0;
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
              };
          };

          helium = {
            enable = true;
            package = heliumPackage;
            flags = heliumFlags;
          };
        };
      };
  };
}
