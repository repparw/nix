{
  pkgs,
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.modules.dlsuite;

  mkContainer = name: attrs:
    mkMerge [
      {
        log-driver = "journald";
        networks = ["dlsuite"];
      }
      attrs
      {
        extraOptions =
          (attrs.extraOptions or [])
          ++ ["--network-alias=${name}"];
      }
    ];

  containersList = [
    (import ./authelia.nix)
    (import ./changedetection.nix)
    (import ./diun.nix)
    (import ./freshrss.nix)
    (import ./jellyfin.nix)
    (import ./ntfy.nix)
    (import ./paperless.nix)
    (import ./arr.nix)
    (import ./swag.nix)
  ];

  containerDefinitions =
    mapAttrs (name: attrs: mkContainer name attrs)
    (foldl' (acc: def: acc // (def {inherit cfg;})) {} containersList);
in {
  options.modules.dlsuite = {
    enable = mkEnableOption "dlsuite container stack services";

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

    user = mkOption {
      type = types.str;
      default = "repparw";
      description = "User to run containers as";
    };

    group = mkOption {
      type = types.str;
      default = "users";
      description = "Group to run containers as";
    };
  };

  config = mkIf cfg.enable {
    virtualisation = {
      podman = {
        autoPrune.enable = true;
        defaultNetwork.settings.dns_enabled = true;
        dockerCompat = true;
      };
      containers = {
        enable = true;
        storage.settings = {
          storage = {
            driver = "btrfs";
          };
        };
      };
    };

    networking.firewall.trustedInterfaces = ["podman*"];
  };
}
