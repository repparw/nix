{ config, lib, ... }:
let
  inherit (lib) types mkOption;
  cfg = config.modules.services;
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

    inventory = mkOption {
      type = types.attrsOf (
        types.submodule {
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
        }
      );
      default = { };
    };
  };
}
