{
  den,
  ...
}:
{
  den.aspects.obsidian = {
    includes = [ den.aspects.rclone ];

    provides.to-hosts.nixos =
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
        workDir = "${config.xdg.stateHome}/rclone/obsidian-bisync";
        filterFile = "${config.xdg.configHome}/rclone/obsidian-bisync.filter";

        obsidianBisync = pkgs.writeShellScript "obsidian-bisync" ''
          set -euo pipefail

          umask 077
          ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg workDir}

          exec ${lib.getExe pkgs.rclone} bisync \
            ${lib.escapeShellArg vault} \
            ${lib.escapeShellArg remote} \
            --workdir ${lib.escapeShellArg workDir} \
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
