{
  den,
  lib,
  ...
}:
{
  den.aspects.alpha = {
    includes = [
      den.aspects.host-common
      den.aspects.backup
      den.aspects.gaming
      den.aspects.logid
      den.aspects.nixos-services
      den.aspects.streaming
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
          };
          kernelModules = [ "kvm-amd" ];
          kernelPackages = pkgs.linuxPackages_latest;
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

          zswap.enable = true;
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
              "nofail"
              "noauto"
              "x-systemd.automount"
              "x-systemd.idle-timeout=10min"
            ];
          };

          "/mnt/seagate" = {
            device = "/dev/disk/by-uuid/979db05c-0fa9-4557-bd92-51f1d10eec3f";
            fsType = "ext4";
            options = [
              "noatime"
              "nodiratime"
              "nofail"
              "noauto"
              "nosuid"
              "nodev"
              "errors=remount-ro"
              "x-systemd.automount"
              "x-systemd.idle-timeout=10min"
            ];
          };
        };

        nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
        hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
        powerManagement.cpuFreqGovernor = "performance";

        swapDevices = [
          {
            device = "/swapfile";
            size = 4096;
          }
        ];

        services = {
          udev.extraRules = ''
            # Disable USB autosuspend for Intel AX210 Bluetooth to fix sleep/wake
            ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="8087", ATTR{idProduct}=="0032", ATTR{power/control}="on"
          '';
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
