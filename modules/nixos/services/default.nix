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
          "glance.icon" = lib.mkDefault "sh:${name}";
          "glance.same-tab" = "true";

          "traefik.http.routers.${name}.tls" = "true";
          "traefik.http.routers.${name}.rule" = lib.mkDefault "Host(`${name}.${cfg.domain}`)";
        };
      }
    ];

  containersList =
    if config.networking.hostName == "alpha" then
      [
        (import ./arr.nix)
        (import ./authelia.nix)
        (import ./changedetection.nix)
        (import ./freshrss.nix)
        (import ./jellyfin.nix)
        # (import ./n8n.nix)
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

  mkFileSystemMount =
    service: subPath:
    {
      "/home/repparw/.config/dlsuite/${service}" = {
        depends = [
          "/"
          "/mnt/hdd"
        ];
        device = "${cfg.configDir}/${subPath}";
        options = [
          "bind"
          "ro"
        ];
      };
    };
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

    fileSystems = mkMerge [
      (mkFileSystemMount "authelia" "authelia")
      (mkFileSystemMount "bazarr" "bazarr/backup")
      (mkFileSystemMount "changedetection" "changedetection")
      (mkFileSystemMount "ddclient" "ddclient")
      (mkFileSystemMount "freshrss" "freshrss")
      (mkFileSystemMount "glance" "glance")
      (mkFileSystemMount "jellyfin" "jellyfin/data/data/backups")
      (mkFileSystemMount "jellyfin-plugins" "jellyfin/data/plugins")
      (mkFileSystemMount "ntfy" "ntfy")
      (mkFileSystemMount "paper" "paper/export")
      (mkFileSystemMount "profilarr" "profilarr/backups")
      (mkFileSystemMount "prowlarr" "prowlarr/Backups")
      (mkFileSystemMount "qbittorrent" "qbittorrent/config")
      (mkFileSystemMount "radarr" "radarr/Backups")
      (mkFileSystemMount "sonarr" "sonarr/Backups")
      (mkFileSystemMount "traefik" "traefik")
    ];
  };
}
