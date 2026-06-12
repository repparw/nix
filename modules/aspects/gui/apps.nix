{
  den,
  inputs,
  lib,
  ...
}:
let
  discordKrispNixpkgs =
    pkgs:
    pkgs.applyPatches {
      name = "nixpkgs-discord-krisp-patched";
      src = inputs.nixpkgs;
      patches = [
        (pkgs.fetchpatch {
          url = "https://github.com/NixOS/nixpkgs/pull/506089.patch";
          hash = "sha256-2aIrsnN9u/fXSgagAqKtzWHR4R+DeWrQ9vCC5bM3ndI=";
        })
      ];
    };
in
{
  den.aspects.gui.provides.guiApps = {
    nixos = {
      nixpkgs.overlays = [
        (final: prev: {
          discord =
            (final.callPackage (
              discordKrispNixpkgs final + "/pkgs/applications/networking/instant-messengers/discord"
            ) { }).discord.override
              {
                withKrisp = true;
              };
        })
        (final: prev: {
          wshowkeys = prev.wshowkeys.overrideAttrs (old: {
            src = prev.fetchFromGitHub {
              owner = "repparw";
              repo = "wshowkeys";
              rev = "52d1191cc250d3a24b83f77ce23f23d498c23bb3";
              hash = "sha256-BkmB+/oG0tsAbvAjkoEAJxObjvg+mCENhM4EHDDXQAI=";
            };
          });
        })
      ];

      programs = {
        gnome-disks.enable = true;
        wshowkeys.enable = true;
      };
      networking.firewall.interfaces.eth0 = {
        # rquickshare
        allowedTCPPorts = [
          32100
        ];
        allowedUDPPorts = [
          5353 # mDNS
          32100
        ];
      };
    };
    homeManager =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      {
        home.packages = with pkgs; [
          pwvucontrol
          scrcpy
          godot
          rquickshare
        ];

        gtk.enable = true;

        xdg.mimeApps.enable = true;

        programs = {
          foot = {
            enable = true;
            settings = {
              colors-dark.blur = true;
            };
          };

          imv = {
            enable = true;
            settings = {
              binds = {
                "<comma>" = "prev";
                "<period>" = "next";
              };
            };
          };

          obsidian = {
            enable = true;
            vaults.repparw = {
              enable = true;
              target = "Documents/obsidian";
            };
            defaultSettings = {
              app = {
                promptDelete = false;
                alwaysUpdateLinks = true;
                vimMode = true;
                userIgnoreFilters = [ "Archive/" ];
                showLineNumber = false;
                showInlineTitle = true;
                attachmentFolderPath = "attachments";
                readableLineLength = true;
              };
              appearance = {
                baseFontSize = lib.mkForce 18;
                showViewHeader = true;
                nativeMenus = false;
                showRibbon = false;
              };
              corePlugins = [
                "backlink"
                "canvas"
                "command-palette"
                "daily-notes"
                "editor-status"
                "file-explorer"
                "file-recovery"
                "global-search"
                "graph"
                "note-composer"
                "outgoing-link"
                "outline"
                "switcher"
                "tag-pane"
                "word-count"
              ];
              hotkeys = {
                "file-explorer:new-file-in-current-tab" = [
                  {
                    modifiers = [ "Mod" ];
                    key = "N";
                  }
                ];
                "file-explorer:new-file" = [ ];
                "editor:insert-codeblock" = [
                  {
                    modifiers = [ "Mod" ];
                    key = "[";
                  }
                ];
                "daily-notes:goto-prev" = [
                  {
                    modifiers = [ "Mod" ];
                    key = "Z";
                  }
                ];
                "daily-notes:goto-next" = [
                  {
                    modifiers = [ "Mod" ];
                    key = "C";
                  }
                ];
                "command-palette:open" = [
                  {
                    modifiers = [
                      "Mod"
                      "Shift"
                    ];
                    key = "P";
                  }
                ];
                "editor:toggle-bullet-list" = [
                  {
                    modifiers = [
                      "Mod"
                      "Shift"
                    ];
                    key = "B";
                  }
                ];
                "switcher:open" = [
                  {
                    modifiers = [ "Mod" ];
                    key = "P";
                  }
                ];
              };
            };
          };

          discord = {
            enable = true;
            settings = {
              minimizeToTray = true;
              arRPC = false;
            };
          };

          element-desktop = {
            enable = true;
          };
        };

        xdg.dataFile."dev.mandre.rquickshare/.settings.json" = {
          text = builtins.toJSON {
            realclose = false;
            autostart = true;
            startminimized = true;
            download_path = config.xdg.userDirs.download;
            port = 32100;
          };
          force = true;
        };
      };

  };
}
