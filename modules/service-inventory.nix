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
      containerAddress = mkOption {
        type = types.nullOr types.str;
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
    };
  };
  validateDefinitions =
    definitions:
    let
      invalid = lib.filterAttrs (
        _: service:
        (service.hostname != null && service.port == null)
        || (service.monitor && (service.hostname == null || service.port == null))
      ) definitions;
      addresses = lib.filter (address: address != null) (
        lib.catAttrs "containerAddress" (lib.attrValues definitions)
      );
      duplicateAddresses = lib.filter (
        address: builtins.length (lib.filter (candidate: candidate == address) addresses) > 1
      ) (lib.unique addresses);
    in
    if invalid != { } then
      throw "invalid service definitions: ${lib.concatStringsSep ", " (lib.attrNames invalid)}; routed and monitored services require both hostname and port"
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
      apply = validateDefinitions;
      description = "Shared service facts used to derive reachability, routing, monitoring, and backups.";
    };

    inventory = mkOption {
      type = types.attrsOf serviceType;
      default = { };
      description = "Legacy service declarations awaiting migration to definitions.";
    };
  };
}
