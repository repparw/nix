{ config, lib, ... }:
let
  inherit (lib) types mkOption;
  cfg = config.modules.services;
  serviceType = types.submodule {
    options = {
      hostname = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      host = mkOption {
        type = types.str;
        description = "Hosting machine name. Remote backends use hostAddresses; the current host uses the container bridge or 127.0.0.1.";
      };
      container = mkOption {
        type = types.bool;
        default = false;
        description = "Whether this service runs in an nspawn container on its host.";
      };
      publishedPort = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "LAN port on the hosting machine when it differs from port.";
      };
      port = mkOption {
        type = types.nullOr types.port;
        default = null;
      };
      auth = mkOption {
        type = types.enum [
          "bypass"
          "one_factor"
          "two_factor"
          "external"
        ];
        default = "one_factor";
      };
      backup = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              path = mkOption { type = types.str; };
            };
          }
        );
        default = null;
      };
      monitor = mkOption {
        type = types.bool;
        default = false;
      };
      healthcheck = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Unauthenticated liveness path. When set, the edge bypasses it and monitors probe https://host/healthcheck.";
      };
      lanEdge = mkOption {
        type = types.bool;
        default = false;
        description = "LAN clients resolve this vhost to lanEdgeHost instead of publicEdgeHost.";
      };
    };
  };
  validateDefinitions =
    hostAddresses: definitions:
    let
      hasValidHostname =
        hostname:
        hostname == null
        || (
          builtins.stringLength hostname <= 63
          && builtins.match "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" hostname != null
        );
      invalid = lib.filterAttrs (
        _: service:
        (service.hostname != null && service.port == null)
        || (service.monitor && (service.hostname == null || service.port == null))
        || (service.healthcheck != null && (service.hostname == null || service.port == null))
      ) definitions;
      invalidHostnames = lib.attrNames (
        lib.filterAttrs (_: service: !hasValidHostname service.hostname) definitions
      );
      unknownHosts = lib.attrNames (
        lib.filterAttrs (_: service: !(lib.hasAttr service.host hostAddresses)) definitions
      );
      hostnames = lib.filter (hostname: hostname != null) (
        lib.catAttrs "hostname" (lib.attrValues definitions)
      );
      duplicateHostnames = lib.filter (
        hostname: builtins.length (lib.filter (candidate: candidate == hostname) hostnames) > 1
      ) (lib.unique hostnames);
    in
    if invalid != { } then
      throw "invalid service definitions: ${lib.concatStringsSep ", " (lib.attrNames invalid)}; routed, monitored, and healthcheck-bearing services require both hostname and port"
    else if invalidHostnames != [ ] then
      throw "invalid service definition hostnames: ${lib.concatStringsSep ", " invalidHostnames}; hostnames must be lowercase DNS labels"
    else if unknownHosts != [ ] then
      throw "service definitions reference hosts missing from modules.services.hostAddresses: ${lib.concatStringsSep ", " unknownHosts}"
    else if duplicateHostnames != [ ] then
      throw "duplicate service definition hostnames: ${lib.concatStringsSep ", " duplicateHostnames}"
    else
      definitions;
in
{
  options.modules.services = {
    rootDir = mkOption {
      type = types.path;
      default = "/home/containers";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/mnt/hdd/media";
    };

    externalDataDir = mkOption {
      type = types.path;
      default = "/mnt/seagate";
    };

    mediaPortalDir = mkOption {
      type = types.path;
      default = "${cfg.rootDir}/media";
    };

    configDir = mkOption {
      type = types.path;
      default = "${cfg.rootDir}/config";
    };

    backupDir = mkOption {
      type = types.path;
      default = "${cfg.rootDir}/backup";
    };

    domain = mkOption {
      type = types.str;
      default = "repparw.com";
    };

    # Discord channel every fleet watcher delivers to (health probe,
    # coredump/disk/reboot watch, update reports, backup size report).
    # The bot token itself stays in the hermes-env sops secret.
    discordChannelId = mkOption {
      type = types.str;
      default = "1515064288191053979";
    };

    definitions = mkOption {
      type = types.attrsOf serviceType;
      default = { };
      apply = validateDefinitions cfg.hostAddresses;
      description = "Shared service facts used to derive reachability, routing, monitoring, and backups.";
    };

    hostAddresses = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Known machines and their LAN addresses for cross-host backend resolution.";
    };

    hostSshAddresses = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "SSH/deploy/LAN-DNS addresses. Defaults to serviceAddress when a host omits sshAddress.";
    };

    lanEdgeHost = mkOption {
      type = types.str;
      default = "pi";
      description = "Host whose sshAddress LAN clients use for lanEdge vhosts.";
    };

    publicEdgeHost = mkOption {
      type = types.str;
      default = "epsilon";
      description = "Host whose sshAddress LAN clients use for public vhosts.";
    };

    bridgePrefix = mkOption {
      type = types.str;
      default = "10.231.136";
      description = "Container bridge subnet prefix (first three octets) for this host's local containers.";
    };

    hostName = mkOption {
      type = types.str;
      default = "";
      description = "Name of the host evaluating this config (== networking.hostName).";
    };

  };

  config.modules.services.hostName = config.networking.hostName;
}
