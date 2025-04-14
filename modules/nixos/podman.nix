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
    };

    # Allow rootless to bind to ports < 1024 (>= 80)
    boot.kernel.sysctl = {"net.ipv4.ip_unprivileged_port_start" = 80;};

    networking.firewall = {
      interfaces."podman*".allowedTCPPorts = [8080 8443]; # Ensure your new ports are allowed for Nginx
      extraForwardRules = ''
        # Redirect HTTP (port 80) to Nginx on port 8080
        tcp dport 80 counter dnat to :8080

        # Redirect HTTPS (port 443) to Nginx on port 8443
        tcp dport 443 counter dnat to :8443
      '';
    };
  };
}
