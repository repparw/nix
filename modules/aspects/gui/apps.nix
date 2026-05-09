{
  den,
  inputs,
  lib,
  ...
}:
{
  flake-file.inputs.nixpkgs-discord-krisp.url = "github:FlameFlag/nixpkgs/flameflag/push-vmswpuqmvzpt";
  # https://github.com/NixOS/nixpkgs/pull/506089

  den.aspects.gui.provides.guiApps = {
    nixos = {
      nixpkgs.overlays = [
        (final: prev: {
          discord =
            (import inputs.nixpkgs-discord-krisp {
              system = prev.system;
              config.allowUnfree = true;
            }).discord.override
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

        gtk = {
          enable = true;
          gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
          gtk4.theme = null;
        };

        xdg.mimeApps = {
          enable = true;
          associations.removed = {
            "application/pdf" = [ "chromium-browser.desktop" ];
          };
          defaultApplications = {
            "inode/directory" = "org.gnome.Nautilus.desktop";
            "application/pdf" = [
              "org.pwmt.zathura.desktop"
              "firefox.desktop"
            ];
            "image/jpeg" = "imv-dir.desktop";
            "image/png" = "imv-dir.desktop";
            "image/gif" = "imv-dir.desktop";
            "text/html" = "firefox.desktop";
            "x-scheme-handler/http" = "firefox.desktop";
            "x-scheme-handler/https" = "firefox.desktop";
            "x-scheme-handler/about" = "firefox.desktop";
            "x-scheme-handler/unknown" = "firefox.desktop";
            "x-scheme-handler/mailto" = "firefox.desktop";
          };
        };

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
