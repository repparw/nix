{
  den,
  ...
}:
{
  den.aspects.obsidian = {
    includes = [ den.aspects.rclone ];

    nixos =
      { config, ... }:
      {
        sops.secrets.rcloneObsidianCrypt = {
          sopsFile = ../../secrets/rclone.sops.yaml;
          owner = config.users.users.repparw.name;
        };
      };

    homeManager =
      {
        osConfig,
        config,
        lib,
        pkgs,
        ...
      }:
      let
        vault = "${config.home.homeDirectory}/Documents/obsidian";
        remote = "obsidian-rs-crypt:";
        filterFile = "${config.xdg.configHome}/rclone/obsidian-bisync.filter";

        obsidianBisync = pkgs.writeShellScript "obsidian-bisync" ''
          set -euo pipefail

          exec ${lib.getExe pkgs.rclone} bisync \
            ${lib.escapeShellArg vault} \
            ${lib.escapeShellArg remote} \
            --filters-file ${lib.escapeShellArg filterFile} \
            --check-access \
            --max-delete 10 \
            --recover \
            --resilient \
            --max-lock 5m \
            --conflict-resolve newer \
            --conflict-loser pathname \
            --conflict-suffix pc,dropbox \
            --log-level INFO
        '';
      in
      {
        programs.obsidian = {
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

        programs.rclone.remotes."obsidian-rs-crypt" = {
          config = {
            type = "crypt";
            remote = "dropbox:Apps/remotely-save/obsidian";
            filename_encoding = "base64";
          };
          secrets.password = osConfig.sops.secrets.rcloneObsidianCrypt.path;
        };

        xdg.configFile."rclone/obsidian-bisync.filter".text = ''
          - /.git/**
          - /.obsidian/**
          - /.trash/**
          - **/.DS_Store
          - **/Thumbs.db
        '';

        systemd.user.services.obsidian-bisync = {
          Unit = {
            Description = "Bidirectional sync for the Obsidian vault";
            Wants = [ "network-online.target" ];
            Requires = [ "rclone-config.service" ];
            After = [
              "network-online.target"
              "rclone-config.service"
            ];
            ConditionPathIsDirectory = vault;
            ConditionPathExists = "${vault}/RCLONE_TEST";
          };

          Service = {
            Type = "oneshot";
            ExecStart = obsidianBisync;
          };
        };

        systemd.user.timers.obsidian-bisync = {
          Unit.Description = "Run Obsidian vault bisync periodically";

          Timer = {
            OnStartupSec = "2m";
            OnUnitInactiveSec = "2m";
            AccuracySec = "15s";
            Unit = "obsidian-bisync.service";
          };

          Install.WantedBy = [ "timers.target" ];
        };
      };
  };
}
