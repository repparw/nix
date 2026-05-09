{
  den,
  lib,
  ...
}:
{
  den.aspects.alpha = {
    includes = [
      den.aspects.host-common
      den.aspects.gaming
      den.aspects.logid
      den.aspects.mercusys-ma530
      den.aspects.nixos-services
      den.aspects.streaming
      den.aspects.timers
      den.aspects.virtual-display
    ];

    nixos =
      {
        config,
        lib,
        modulesPath,
        ...
      }:
      {
        imports = [
          (modulesPath + "/installer/scan/not-detected.nix")
        ];

        boot = {
          initrd = {
            systemd.enable = true;
            availableKernelModules = [
              "nvme"
              "xhci_pci"
              "ahci"
              "usbhid"
              "usb_storage"
              "uas"
              "sd_mod"
            ];
          };
          kernelModules = [ "kvm-amd" ];
          loader = {
            systemd-boot = {
              enable = true;
              configurationLimit = 10;
              consoleMode = "max";
            };
            timeout = 1;
            efi.canTouchEfiVariables = true;
          };
          tmp.useTmpfs = true;
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

          "/mnt/hdd" = {
            fsType = "btrfs";
            label = "HDD";
            options = [
              "noatime"
              "nodiratime"
              "noauto"
              "x-systemd.automount"
              "x-systemd.idle-timeout=60"
              "x-systemd.device-timeout=5s"
              "nofail"
            ];
          };

          "/mnt/seagate" = {
            device = "/dev/disk/by-uuid/979db05c-0fa9-4557-bd92-51f1d10eec3f";
            fsType = "ext4";
            options = [
              "noauto"
              "x-systemd.automount"
              "x-systemd.idle-timeout=60"
              "x-systemd.device-timeout=5s"
              "nofail"
              "nosuid"
              "nodev"
              "relatime"
              "errors=remount-ro"
            ];
          };
        };

        nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
        hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

        programs.obs-studio.enable = true;

        zramSwap.enable = true;

        services = {
          archisteamfarm = {
            enable = true;
            bots.repparw = {
              settings.OnlineStatus = 0;
              username = "ulisesbritos1";
              passwordFile = config.sops.secrets.steamPassword.path;
            };
          };
        };
      };

    homeManager = {
      services.spotifyd = {
        enable = true;
        settings.global = {
          username = "2ksy00sfypgevoabx2128ia4g";
          device_name = "alpha";
          bitrate = 320;
          max_cache_size = 5000000000;
          initial_volume = 50;
          volume_normalisation = false;
        };
      };

      systemd.user.services.spotifyd = {
        Unit.After = [ "network-online.target" ];
        Service.RuntimeMaxSec = "6h";
      };
    };
  };
}
