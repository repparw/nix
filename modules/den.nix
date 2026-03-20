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

  den.schema.user.classes = lib.mkDefault [ "homeManager" ];

  den.hosts.x86_64-linux.alpha.users.repparw = { };
  den.hosts.x86_64-linux.beta.users.repparw = { };

  den.aspects.repparw = {
    includes = [
      den.provides.define-user
      den.provides.primary-user
      den.aspects.shell
      den.aspects.tmux
      den.aspects.git
      den.aspects.editors
      den.aspects.file-manager
      den.aspects.scripts
      den.aspects.rclone
      den.aspects.gui-core
      den.aspects.jellyfin-mpv-shim
      den.aspects.kanshi
    ];

    homeManager =
      { ... }:
      {
        home.username = "repparw";
        home.homeDirectory = "/home/repparw";
        home.stateVersion = "25.05";
        xdg.enable = true;
        home.preferXdgDirectories = true;
        services.udiskie = {
          enable = true;
          tray = "never";
        };
      };
  };

  den.aspects.alpha = {
    includes = [
      den.provides.hostname
      den.aspects.nixos-base
      den.aspects.secrets
      den.aspects.vm
      den.aspects.cli-core
      den.aspects.gui-core
      den.aspects.gaming
      den.aspects.nixos-services
      den.aspects.style
      den.aspects.auto-upgrade
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
            };
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
        };

        swapDevices = [ ];

        nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
        hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

        modules = {
          gaming.enable = true;
          services.enable = true;
          timers.enable = true;
          virtualDisplay.enable = true;
        };

        programs.obs-studio.enable = true;

        networking.hostName = "alpha";

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

          sunshine = {
            enable = true;
            openFirewall = true;
            capSysAdmin = true;
            settings = {
              output_name = 2;
            };
            applications.apps = [
              {
                name = "Steam Big Picture";
                prep-cmd = [
                  {
                    do = "niri msg action focus-monitor DP-2";
                    undo = "niri msg action focus-monitor DP-1";
                  }
                  {
                    do = "";
                    undo = "setsid steam steam://close/bigpicture";
                  }
                ];
                detached-commands = [ "setsid steam steam://open/bigpicture" ];
                auto-detach = "true";
              }
            ];
          };
        };

        system.stateVersion = "25.11";
      };

    homeManager = { ... }: { };
  };

  den.aspects.beta = {
    includes = [
      den.provides.hostname
      den.aspects.nixos-base
      den.aspects.secrets
      den.aspects.vm
      den.aspects.cli-core
      den.aspects.gui-core
      den.aspects.style
      den.aspects.auto-upgrade
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
            availableKernelModules = [
              "xhci_pci"
              "ehci_pci"
              "ahci"
              "usb_storage"
              "sd_mod"
              "rtsx_pci_sdmmc"
            ];
            kernelModules = [ ];
          };
          kernelModules = [ "kvm-intel" ];
          extraModprobeConfig = ''
            options thinkpad_acpi force_load=1 fan_control=1
          '';
          loader = {
            systemd-boot = {
              enable = true;
            };
            efi.canTouchEfiVariables = true;
          };
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

        swapDevices = [ ];

        nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
        hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

        networking.hostName = "beta";

        services = {
          logind.settings.Login.HandleLidSwitchExternalPower = "ignore";
          tlp.enable = true;
        };

        system.stateVersion = "25.11";
      };

    homeManager =
      { pkgs, ... }:
      {
        modules.kanshi.enable = true;
        home.packages = [ pkgs.brightnessctl ];
      };
  };
}
