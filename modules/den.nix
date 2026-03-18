{
  inputs,
  den,
  lib,
  ...
}:
{
  imports = [
    inputs.den.flakeModule
  ];

  den.ctx.user.classes = lib.mkDefault [ "homeManager" ];

  den.hosts.x86_64-linux.alpha.users.repparw = {};
  den.hosts.x86_64-linux.beta.users.repparw = {};

  den.aspects.repparw = {
    includes = [
      den.provides.define-user
      den.provides.primary-user
      den.aspects.cli
      den.aspects.shellFish
      den.aspects.userRepparw
    ];
  };

  den.aspects.alpha = {
    includes = [
      den.provides.hostname
      den.aspects.nixos-base
      den.aspects.secrets
      den.aspects.vms
      den.aspects.cli
      den.aspects.gui
      den.aspects.niri
      den.aspects.hyprland
      den.aspects.gaming
      den.aspects.nixos-services
    ];

    nixos = { pkgs, ... }: {
      boot.loader = {
        systemd-boot = {
          enable = true;
          configurationLimit = 10;
        };
        efi.canTouchEfiVariables = true;
      };

      fileSystems = {
        "/" = {
          device = "/dev/disk/by-uuid/51c5e80b-e22e-4d62-a3e2-ebb531deb05b";
          fsType = "btrfs";
          options = [ "subvol=@" ];
        };

        "/boot" = {
          device = "/dev/disk/by-uuid/FBF2-5114";
          fsType = "vfat";
          options = [
            "fmask=0137"
            "dmask=0027"
          ];
        };
      };

      system.stateVersion = "25.11";
    };
  };

  den.aspects.beta = {
    includes = [
      den.provides.hostname
      den.aspects.nixos-base
      den.aspects.secrets
      den.aspects.vms
      den.aspects.cli
      den.aspects.gui
      den.aspects.niri
    ];

    nixos = { pkgs, ... }: {
      boot.loader = {
        systemd-boot = {
          enable = true;
        };
        efi.canTouchEfiVariables = true;
      };

      fileSystems = {
        "/" = {
          device = "/dev/disk/by-uuid/198b9a58-8838-440f-b2e7-1181826dda06";
          fsType = "ext4";
        };

        "/boot" = {
          device = "/dev/disk/by-uuid/F868-A3C4";
          fsType = "vfat";
          options = [
            "fmask=0137"
            "dmask=0027"
          ];
        };
      };

      system.stateVersion = "25.11";
    };
  };
}
