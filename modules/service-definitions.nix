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
      };auth = mkOption {
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
        || (service.host != null && !(lib.hasAttr service.host hostAddresses))
      ) definitions;
      invalidHostnames = lib.attrNames (
        lib.filterAttrs (_: service: !hasValidHostname service.hostname) definitions
      );
      unknownHosts = lib.attrNames (
        lib.filterAttrs (_: service: service.host != null && !(lib.hasAttr service.host hostAddresses)) definitions
      );
      hostnames = lib.filter (hostname: hostname != null) (
        lib.catAttrs "hostname" (lib.attrValues definitions)
      );
      duplicateHostnames = lib.filter (
        hostname: builtins.length (lib.filter (candidate: candidate == hostname) hostnames) > 1
      ) (lib.unique hostnames);
      addresses = lib.filter (address: address != null) (
        lib.catAttrs "containerAddress" (lib.attrValues definitions)
      );
      duplicateAddresses = lib.filter (
        address: builtins.length (lib.filter (candidate: candidate == address) addresses) > 1
      ) (lib.unique addresses);
    in
    if invalid != { } then
      throw "invalid service definitions: ${lib.concatStringsSep ", " (lib.attrNames invalid)}; routed and monitored services require both hostname and port"
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

    timezone = mkOption {
      type = types.str;
      default = "America/Argentina/Buenos_Aires";
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

  };
}
