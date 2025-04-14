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
        log-driver = "journald";
        networkMode = "dlsuite";
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
  };

  config = mkIf cfg.enable {
    services.podman = {
      enable = true;
      containers = containerDefinitions;
      settings = {
        storage = {
          driver = "btrfs";
        };
      };
    };
  };
}
