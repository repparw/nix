{
  den,
  lib,
  ...
}:
{
  den.aspects.gui-apps = {
    includes = [ ];

    homeManager =
      {
        config,
        osConfig,
        pkgs,
        lib,
        ...
      }:
      let
        guiEnabled = osConfig.modules.gui.enable or false;
        niriEnabled = osConfig.programs.niri.enable or false;
      in
      {
        config = lib.mkIf guiEnabled {
          services.wpaperd.enable = lib.mkIf niriEnabled true;

          home.packages = with pkgs; [
            pwvucontrol
            scrcpy
            godot
            anki
            rquickshare
          ];

          gtk = {
            enable = true;
            gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
          };

          xdg.mimeApps = {
            enable = true;
            associations.removed = {
              "application/pdf" = [ "chromium-browser.desktop" ];
              "inode/directory" = [ "firefox.desktop" ];
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
            foot.enable = true;

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
                  newFileLocation = "folder";
                  newFileFolderPath = "05 - Fleeting";
                  attachmentFolderPath = "attachments";
                  readableLineLength = true;
                };
                appearance = lib.mkForce {
                  baseFontSize = lib.mkForce 18;
                  theme = "obsidian";
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

            vesktop = {
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

          systemd.user.services.rquickshare = {
            Unit = {
              Description = "RQuickShare - Quick Share for Linux";
              After = [ "graphical-session.target" ];
              Wants = [ "graphical-session.target" ];
            };
            Service = {
              Type = "simple";
              ExecStart = "${pkgs.rquickshare}/bin/rquickshare";
              Restart = "on-failure";
              RestartSec = 5;
            };
            Install = {
              WantedBy = [ "default.target" ];
            };
          };
        };
      };
  };
}
