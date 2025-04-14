{
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.modules.services;

  mkContainer = name: attrs:
    mkMerge [
      {
        networks = ["net"];
      }
      attrs
      {
        extraOptions =
          (attrs.extraOptions or [])
          ++ [
            "--network-alias=${name}"
          ];
      }
    ];

  containersList = [
    (import ./arr.nix)
    (import ./authelia.nix)
    (import ./changedetection.nix)
    (import ./diun.nix)
    (import ./freshrss.nix)
    (import ./jellyfin.nix)
    (import ./ntfy.nix)
    (import ./paperless.nix)
    (import ./proxy.nix)
  ];

  containerDefinitions =
    mapAttrs (name: attrs: mkContainer name attrs)
    (foldl' (acc: def: acc // (def {inherit cfg;})) {} containersList);
in {
  options.modules.services = {
    enable = mkEnableOption "podman container services";

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

    networking.firewall.trustedInterfaces = ["podman*"];
  };
}
