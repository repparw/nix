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

      oci-containers.backend = "podman";
      oci-containers.containers = containerDefinitions;
    };

    networking.firewall.trustedInterfaces = ["podman*"];

    # users.users.dlsuite = {
    #   isNormalUser = true;
    #   uid = lib.strings.toInt cfg.user;
    #   group = "docker";
    #   home = "/home/docker";
    #   homeMode = "755";
    #   createHome = false;
    #   shell = pkgs.bash;
    # };

    # Services
    systemd.services = let
      containerSuffixes = builtins.attrNames containerDefinitions;

      mkSystemService = suffix: {
        "podman-${suffix}" = {
          serviceConfig = {
            User = lib.mkForce cfg.user;
            Group = cfg.group;
          };
          after = [
            "podman-network-dlsuite.service"
          ];
          requires = [
            "podman-network-dlsuite.service"
          ];
          partOf = [
            "dlsuite.target"
          ];
          wantedBy = [
            "dlsuite.target"
          ];
        };
      };

      systemdServices =
        builtins.foldl' lib.recursiveUpdate {} (map mkSystemService containerSuffixes);
    in
      systemdServices
      // {
        # Networks
        "podman-network-dlsuite" = {
          path = [
            pkgs.podman
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStop = "podman network rm -f dlsuite";
          };
          script = ''
            podman network inspect dlsuite || podman network create dlsuite
          '';
          partOf = [
            "dlsuite.target"
          ];
          wantedBy = [
            "dlsuite.target"
          ];
        };
      };

    # Root service
    # When started, this will automatically create all resources and start
    # the containers. When stopped, this will teardown all resources.
    systemd.targets."dlsuite" = {
      unitConfig = {
        Description = "Root target as alternative to compose";
      };
      wantedBy = [
        "multi-user.target"
      ];
    };
  };
}
