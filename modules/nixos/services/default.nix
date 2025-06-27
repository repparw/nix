{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.modules.services;

  mkContainer =
    name: attrs:
    mkMerge [
      attrs
      {
        extraOptions = (attrs.extraOptions or [ ]) ++ [
          "--network-alias=${name}"
        ];
        labels = (attrs.labels or { }) // {
          "io.containers.autoupdate" = "registry";

          "glance.name" = name;
          "glance.url" = lib.mkDefault "https://${name}.${cfg.domain}";
          "glance.icon" = lib.mkDefault "di:${name}";
          "glance.same-tab" = "true";

          "traefik.http.routers.${name}.tls" = "true";
          "traefik.http.routers.${name}.rule" = lib.mkDefault "Host(`${name}.${cfg.domain}`)";
        };
      }
    ];

  containersList =
    if config.networking.hostName == "alpha" then
      [
        (import ./actual.nix)
        (import ./arr.nix)
        (import ./authelia.nix)
        (import ./changedetection.nix)
        (import ./diun.nix)
        (import ./freshrss.nix)
        (import ./jellyfin.nix)
        (import ./n8n.nix)
        (import ./ntfy.nix)
        (import ./paperless.nix)
        (import ./proxy.nix)
      ]
    else if config.networking.hostName == "pi" then
      [
        (import ./homeassistant.nix)
        (import ./hyperion.nix)
        (import ./pihole.nix)
        # (import ./proxy.nix)
      ]
    else
      [ ];

  containerDefinitions = mapAttrs (name: attrs: mkContainer name attrs) (
    foldl' (acc: def: acc // (def { inherit cfg config; })) { } containersList
  );
in
{
  options.modules.services = {
    enable = mkEnableOption "podman container services";

    rootDir = mkOption {
      type = types.path;
      default = "/home/docker";
      description = "Root directory for the containers";
    };

    dataDir = mkOption {
      type = types.path;
      default = "${cfg.rootDir}/data";
      description = "Directory to store container data";
    };

    configDir = mkOption {
      type = types.path;
      default = "${cfg.rootDir}/config";
      description = "Directory to store container config";
    };

    timezone = mkOption {
      type = types.str;
      default = "America/Argentina/Buenos_Aires";
      description = "Timezone for containers";
    };

    domain = mkOption {
      type = types.str;
      default = "repparw.me";
      description = "Base domain for the services";
    };

    user = mkOption {
      type = types.str;
      default = "1000";
      description = "User to run the containers";
    };
    group = mkOption {
      type = types.str;
      default = "100";
      description = "Group to run the containers";
    };
  };

  config = mkIf cfg.enable {
    systemd.timers.podman-auto-update.wantedBy = [ "multi-user.target" ];

    virtualisation = {
      podman = {
        enable = true;
        autoPrune.enable = true;
        defaultNetwork.settings.dns_enabled = true;
      };

      oci-containers.containers = containerDefinitions;

      containers = {
        enable = true;
        storage.settings = {
          storage = {
            driver = "btrfs";
          };
        };
      };
    };

    networking.firewall.trustedInterfaces = [ "podman*" ];

    fileSystems = {
      "/home/repparw/.config/dlsuite/actual" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/actual";
        options = [
          "bind"
          "ro"
        ];
      };

      "/home/repparw/.config/dlsuite/authelia" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/authelia";
        options = [
          "bind"
          "ro"
        ];
      };

      "/home/repparw/.config/dlsuite/bazarr" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/bazarr/backup";
        options = [
          "bind"
          "ro"
        ];
      };

      "/home/repparw/.config/dlsuite/changedetection" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/changedetection";
        options = [
          "bind"
          "ro"
        ];
      };

      "/home/repparw/.config/dlsuite/ddclient" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/ddclient";
        options = [
          "bind"
          "ro"
        ];
      };

      "/home/repparw/.config/dlsuite/diun" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/diun";
        options = [
          "bind"
          "ro"
        ];
      };

      "/home/repparw/.config/dlsuite/freshrss" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/freshrss";
        options = [
          "bind"
          "ro"
        ];
      };

      "/home/repparw/.config/dlsuite/glance" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/glance";
        options = [
          "bind"
          "ro"
        ];
      };

      # "/home/repparw/.config/dlsuite/jellyfin" = {
      #   depends = [
      #     "/"
      #     "/mnt/hdd"
      #   ];
      #   device = "${cfg.configDir}/jellyfin";
      #   options = [
      #     "bind"
      #     "ro"
      #   ];
      # }; # TODO  change to backup dir for auto backup

      "/home/repparw/.config/dlsuite/ntfy" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/ntfy";
        options = [
          "bind"
          "ro"
        ];
      };

      "/home/repparw/.config/dlsuite/paper" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/paper/export";
        options = [
          "bind"
          "ro"
        ];
      };

      "/home/repparw/.config/dlsuite/prowlarr" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/prowlarr/Backups";
        options = [
          "bind"
          "ro"
        ];
      };

      "/home/repparw/.config/dlsuite/qbittorrent" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/qbittorrent/config";
        options = [
          "bind"
          "ro"
        ];
      };

      "/home/repparw/.config/dlsuite/radarr" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/radarr/Backups";
        options = [
          "bind"
          "ro"
        ];
      };

      "/home/repparw/.config/dlsuite/sonarr" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/sonarr/Backups";
        options = [
          "bind"
          "ro"
        ];
      };

      "/home/repparw/.config/dlsuite/traefik" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/traefik";
        options = [
          "bind"
          "ro"
        ];
      };
    };
  };
}
