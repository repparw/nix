{
  den,
  inputs,
  ...
}:
let
  tasksOrgNixpkgs =
    pkgs:
    pkgs.applyPatches {
      name = "nixpkgs-tasks-org-patched";
      src = inputs.nixpkgs;
      patches = [
        (pkgs.fetchpatch {
          url = "https://github.com/repparw/nixpkgs/commit/e028238040c0f51d375b78cee86c41897c2c4a9c.patch";
          hash = "sha256-riDWftnTjjeJTmCKfo6LzwlwfDWr8tUKusWuveBOrJw=";
        })
      ];
    };
in
{
  flake-file.inputs.nixcord = {
    url = "github:FlameFlag/nixcord";
  };

  den.aspects.gui.provides.guiApps = {
    nixos =
      { pkgs, ... }:
      {
        nixpkgs.overlays = [
          (final: prev: {
            tasks-org = final.callPackage (
              tasksOrgNixpkgs final + "/pkgs/by-name/ta/tasks-org/package.nix"
            ) { };
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
        environment.systemPackages = [ pkgs.qalculate-gtk ];
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
          tasks-org
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

          nixcord = {
            enable = true;
            discord = {
              krisp.enable = true;
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
