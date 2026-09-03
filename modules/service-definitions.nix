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
      # Machine hosting the service. null keeps addressing host-local
      # (containerAddress or loopback); set to the hosting machine's name so
      # other hosts resolve the backend through its LAN address.
      host = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      containerAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      container = mkOption {
        type = types.bool;
        default = false;
        description = "Whether this service runs in an nspawn container on its host.";
      };
      # Port exposed on the hosting machine's LAN when it differs from
      # `port` (e.g. two containers behind one host publishing the same
      # container port). Only meaningful together with `host`.
      publishedPort = mkOption {
        type = types.nullOr types.port;
        default = null;
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
      # Unauthenticated HTTP path the service serves to signal liveness
      # (e.g. miniflux /healthcheck, servarr /ping). When set, the service
      # becomes publicly probeable through the edge: authelia bypasses it and
      # monitors (glance, fleet-health) check it via https://host/healthcheck.
      healthcheck = mkOption {
        type = types.nullOr types.str;
        default = null;
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
        lib.filterAttrs (
          _: service: service.host != null && !(lib.hasAttr service.host hostAddresses)
        ) definitions
      );
      hostnames = lib.filter (hostname: hostname != null) (
        lib.catAttrs "hostname" (lib.attrValues definitions)
      );
      duplicateHostnames = lib.filter (
        hostname: builtins.length (lib.filter (candidate: candidate == hostname) hostnames) > 1
      ) (lib.unique hostnames);
      addresses =
        let
          # containerAddress lives in each host's own bridge namespace
          # (every host runs 10.231.136.0/24), so uniqueness is scoped per
          # owning host: "local" means this host's own bridge.
          perHost = lib.mapAttrsToList (_: service: {
            inherit (service) containerAddress;
            scope = if service.host == null then "local" else service.host;
          }) definitions;
        in
        map (entry: "${entry.scope} ${entry.containerAddress}") (
          lib.filter (entry: entry.containerAddress != null) perHost
        );
      duplicateAddresses = lib.filter (
        address: builtins.length (lib.filter (candidate: candidate == address) addresses) > 1
      ) (lib.unique addresses);
    in
    if invalid != { } then
      throw "invalid service definitions: ${lib.concatStringsSep ", " (lib.attrNames invalid)}; routed, monitored, and healthcheck-bearing services require both hostname and port"
    else if invalidHostnames != [ ] then
      throw "invalid service definition hostnames: ${lib.concatStringsSep ", " invalidHostnames}; hostnames must be lowercase DNS labels"
    else if unknownHosts != [ ] then
      throw "service definitions reference hosts missing from modules.services.hostAddresses: ${lib.concatStringsSep ", " unknownHosts}"
    else if duplicateHostnames != [ ] then
      throw "duplicate service definition hostnames: ${lib.concatStringsSep ", " duplicateHostnames}"
    else if duplicateAddresses != [ ] then
      throw "duplicate service definition container addresses: ${lib.concatStringsSep ", " duplicateAddresses}"
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

    definitions = mkOption {
      type = types.attrsOf serviceType;
      default = { };
      apply = validateDefinitions cfg.hostAddresses;
      description = "Shared service facts used to derive reachability, routing, monitoring, and backups.";
    };

    # LAN address of each known machine, keyed by host name. Definitions with
    # a `host` set resolve their loopback-bound backends through this map;
    # containerAddress backends are reached directly via the hosting machine's
    # routed container bridge.
    hostAddresses = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        alpha = "192.168.0.18";
        pi = "192.168.0.4";
      };
      description = "Known machines and their LAN addresses for cross-host backend resolution.";
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
