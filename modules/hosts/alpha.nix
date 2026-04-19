{
  den,
  lib,
  ...
}:
{
  den.aspects.alpha = {
    includes = [
      den.provides.hostname
      den.aspects.auto-upgrade
      den.aspects.cli
      den.aspects.gaming
      den.aspects.logid
      den.aspects.networking
      den.aspects.nixos-services
      den.aspects.overlays
      den.aspects.repparw
      den.aspects.secrets
      den.aspects.style
      den.aspects.streaming
      den.aspects.timers
      den.aspects.virtual-display
    ];

    nixos =
      {
        config,
        lib,
        pkgs,
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
            kernelModules = [ ];
          };
          kernelModules = [ "kvm-amd" ];
          extraModulePackages = [ ];
          loader = {
            systemd-boot = {
              enable = true;
              configurationLimit = 10;
              consoleMode = "max";
            };
            timeout = 1;
            efi.canTouchEfiVariables = true;
          };
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

        swapDevices = [ ];

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

          beesd.filesystems = {
            root = {
              spec = "LABEL=root";
              hashTableSizeMB = 4096;
              verbosity = "crit";
              extraOptions = [
                "--loadavg-target"
                "5.0"
              ];
            };
            hdd = {
              spec = "LABEL=HDD";
              verbosity = "crit";
              extraOptions = [
                "--loadavg-target"
                "5.0"
              ];
            };
          };

        };
      };

    provides.repparw.homeManager = {
      services.spotifyd = {
        enable = true;
        settings.global = {
          username = "2ksy00sfypgevoabx2128ia4g";
          device_name = "alpha";
          bitrate = 320;
          max_cache_size = 5000000000;
          initial_volume = 70;
          volume_normalisation = false;
        };
      };
    };
  };
}
