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
        heliumPackage = lib.makeOverridable (
          {
            flags ? config.programs.helium.flags,
          }:
          let
            base = inputs.helium-nix.packages.${pkgs.stdenv.hostPlatform.system}.helium.override {
              inherit flags;
            };
            launcher = pkgs.writeShellApplication {
              name = "helium";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.findutils
              ];
              text = ''
                # Preserve extension storage before version changes (Helium #1978).
                snapshotRoot="''${XDG_STATE_HOME:-$HOME/.local/state}/helium-extension-snapshots"
                marker="$snapshotRoot/launched-version"
                defaultDir="$HOME/.config/net.imput.helium/Default"
                if [ "$(cat "$marker" 2>/dev/null)" != "${base.name}" ]; then
                  dest="$snapshotRoot/pre-${base.name}"
                  if [ ! -d "$dest" ]; then
                    mkdir -p "$dest"
                    for dir in "Local Extension Settings" "Sync Extension Settings"; do
                      if [ -d "$defaultDir/$dir" ]; then
                        cp -a "$defaultDir/$dir" "$dest/"
                      fi
                    done
                  fi
                  find "$snapshotRoot" -maxdepth 1 -name 'pre-*' -type d | sort -r | tail -n +4 | xargs -r rm -rf
                  printf '%s' "${base.name}" > "$marker"
                fi
                exec ${base}/bin/helium "$@"
              '';
            };
          in
          pkgs.symlinkJoin {
            name = "${base.name}-configured";
            paths = [ base ];
            postBuild = ''
              rm "$out/bin/helium"
              install -Dm755 ${launcher}/bin/helium "$out/bin/helium"
              rm -rf "$out/share/applications"
              install -Dm644 ${base}/share/applications/helium.desktop \
                "$out/share/applications/helium.desktop"
              # App-menu launches must use the same snapshot launcher as webapps.
              sed -i -E '/^MimeType=/d; s|^Exec=[^ ]*/bin/helium|Exec='"$out"'/bin/helium|' \
                "$out/share/applications/helium.desktop"
            '';
            inherit (base) meta;
          }
        ) { };
        heliumFlags = [
          # Upstream's wrapper adds an inert '${NIXOS_OZONE_WL:+...}' literal
          # instead of a real shell expansion, so set the hint here. "auto"
          # picks Wayland when available and X11 otherwise.
          "--ozone-platform-hint=auto"
          "--force-renderer-accessibility"
          "--silent-debugger-extension-api"
          # OSCrypt backend must be identical for normal windows and
          # --app webapps: they share ~/.config/net.imput.helium, and
          # Chromium honors the first process's backend. Mixed backends
          # (basic vs libsecret) rewrite Local State without an
          # encrypted_key and orphan cookie encryption keys, which drops
          # Google/YouTube session cookies on the next start. basic
          # persists without requiring an unlocked login keyring.
          "--password-store=basic"
          # Unpacked MV3 extension that hands external links clicked in the
          # WhatsApp web app to Firefox. It has no stored settings, so the
          # extension-state wipes cannot disable it. See the package for why
          # the store "Open in Firefox" extension does not cover this.
          "--load-extension=${whatsappLinksToFirefox}"
        ];
        # Helium's user-data-dir on Linux is ~/.config/net.imput.helium
        # (verified: live Default/, SingletonSocket, and crashpad database
        # all live there). NativeMessagingHosts must go under it;
        # ~/.config/helium is not read by the browser.
        heliumConfigDir = ".config/net.imput.helium";
      in
      {
        imports = [ inputs.helium-nix.homeModules.default ];

        home.packages = [
          (pkgs.writeShellApplication {
            name = "webapp";
            runtimeInputs = [
              heliumPackage
              ndrop
            ];
            text = ''
              if [ "$#" -lt 2 ]; then
                echo "usage: webapp <app-id> <url> [helium args...]" >&2
                exit 2
              fi

              app_id="$1"
              url="$2"
              shift 2

              # Helium/Chromium on native Wayland ignores --class for --app
              # windows and exposes a derived app_id of the form
              # chrome-<host>__<path>-Default (e.g. https://www.youtube.com
              # becomes chrome-www.youtube.com__-Default, verified via
              # `niri msg windows`). Derive it so ndrop exact-matches the
              # existing window instead of spawning a duplicate.
              # NOTE: --class is intentionally not passed: it is ignored for
              # --app windows, and when the webapp starts the first browser
              # process it would mislabel later normal windows with the
              # webapp name instead of "helium".
              no_scheme="''${url#https://}"
              no_scheme="''${no_scheme#http://}"
              no_scheme="''${no_scheme%%[?#]*}"
              case "$no_scheme" in
                */*)
                  authority="''${no_scheme%%/*}"
                  path="/''${no_scheme#*/}"
                  ;;
                *)
                  authority="$no_scheme"
                  path="/"
                  ;;
              esac

              # Chromium builds the application name as host + "_" + URL path,
              # then sanitizes path separators for its Linux desktop/XDG ID.
              # Keep the leading/trailing path separators: /foo/ must become
              # __foo_ rather than __foo, otherwise ndrop misses the window.
              host="''${authority##*@}"
              case "$host" in
                \[*\]:*)
                  host="''${host%%]:*}]"
                  ;;
                \[*\])
                  ;;
                *:*)
                  host="''${host%%:*}"
                  ;;
              esac
              host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"

              if [ -n "$host" ]; then
                app_name="$(printf '%s_%s' "$host" "$path" | tr '/ ' '__')"
                chrome_id="chrome-''${app_name}-Default"
              else
                chrome_id="$app_id"
              fi

              exec ndrop -F -c "$chrome_id" \
                helium \
                --app="$url" \
                "$@"
            '';
          })
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
