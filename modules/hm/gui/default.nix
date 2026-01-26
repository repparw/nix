{
  config,
  osConfig,
  pkgs,
  lib,
  ...
}:
let
  cfg = osConfig.modules.gui;
in
{
  imports = [
    ./firefox
    ./gaming.nix
    ./jellyfin-mpv-shim.nix
    ./kanshi.nix
    ./mpv.nix
    ./obs.nix
    ./spotify.nix
    ./wm
    ./zathura.nix
  ];

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      pwvucontrol
      scrcpy

      godot

      anki

      planify
      # find pomo app in nixpkgs
    ];

    gtk = {
      enable = true;
      gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
    };

    xdg = {
      mimeApps = {
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
    };

    programs = {
      chromium.enable = true;

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
          # appearance = lib.mkForce {
          #   showViewHeader = true;
          #   nativeMenus = false;
          #   showRibbon = false;
          # };
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
          # communityPlugins = [
          #   "vimrc-support"
          #   "remotely-save"
          #   "obsidian-git"
          # ];
          hotkeys = {
            "file-explorer:new-file-in-current-tab" = [
              {
                modifiers = [ "Mod" ];
                key = "N";
              }
            ];
            "file-explorer:new-file" = [
              {
                modifiers = [ ];
                key = "";
              }
            ];
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
    };
  };
}
