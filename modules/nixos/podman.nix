{
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.modules.podman;
in {
  options.modules.podman = {
    enable = mkEnableOption "System-wide podman configuration";

    dataDir = mkOption {
      type = types.path;
      default = "/home/docker";
      description = "Directory to store container data";
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
  };

  config = mkIf cfg.enable {
    virtualisation = {
      podman = {
        enable = true;
        autoPrune.enable = true;
        defaultNetwork.settings.dns_enabled = true;
      };
      containers = {
        enable = true;
        storage.settings = {
          storage = {
            driver = "btrfs";
          };
        };
      };

      oci-containers = {
        backend = "podman";
        containers = {
          "swag" = {
            image = "docker.io/linuxserver/swag:latest";
            environment = {
              "DNSPLUGIN" = "cloudflare";
              "PUID" = "1000";
              "PGID" = "100";
              "TZ" = cfg.timezone;
              "SUBDOMAINS" = "wildcard";
              "URL" = cfg.domain;
              "VALIDATION" = "dns";
            };
            volumes = [
              "${cfg.dataDir}/swag:/config:rw,Z"
            ];
            ports = [
              "80:80/tcp"
              "443:443/tcp"
            ];
          };

          "ddclient" = {
            image = "docker.io/linuxserver/ddclient:latest";
            environment = {
              "PUID" = "1000";
              "PGID" = "100";
              "TZ" = cfg.timezone;
            };
            volumes = [
              "${cfg.dataDir}/ddclient:/config:rw,Z"
            ];
          };
        };
      };
    };

    boot.kernel.sysctl = {"net.ipv4.ip_unprivileged_port_start" = 0;};
    networking.firewall.enable = true;
    networking.firewall.allowedTCPPorts = [80 443];
    networking.firewall.allowedUDPPorts = [80 443];

    networking.firewall.trustedInterfaces = ["podman*"];
  };
}
