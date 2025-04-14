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
    # Enable and configure podman service
    services.podman = {
      enable = true;
      autoPrune.enable = true;
      defaultNetwork.settings.dns_enabled = true;
      # Configure containers
      containers = containerDefinitions;
    };

    # Create systemd services for network and coordination
    systemd.user.services = {
      "podman-network-dlsuite" = {
        Unit = {
          Description = "Podman network for dlsuite services";
          PartOf = ["dlsuite.target"];
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.podman}/bin/podman network inspect dlsuite || ${pkgs.podman}/bin/podman network create dlsuite";
          ExecStop = "${pkgs.podman}/bin/podman network rm -f dlsuite";
        };
        Install.WantedBy = ["dlsuite.target"];
      };
    };

    # Root target service
    systemd.user.targets.dlsuite = {
      Unit = {
        Description = "DLSuite services target";
        Requires = ["podman-network-dlsuite.service"];
      };
      Install.WantedBy = ["default.target"];
    };

    # Add container service dependencies
    systemd.user.services = let
      containerSuffixes = builtins.attrNames containerDefinitions;

      mkSystemService = suffix: {
        "podman-${suffix}" = {
          Unit = {
            After = ["podman-network-dlsuite.service"];
            Requires = ["podman-network-dlsuite.service"];
            PartOf = ["dlsuite.target"];
          };
          Install.WantedBy = ["dlsuite.target"];
        };
      };
    in
      builtins.foldl' lib.recursiveUpdate {} (map mkSystemService containerSuffixes);
  };
}
