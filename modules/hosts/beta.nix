{
  den,
  lib,
  ...
}:
{
  den.aspects.beta = {
    includes = [
      den.aspects.host-common
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

        services = {
          keyd = {
            enable = true;
            keyboards.default.settings.main.capslock = "overload(control, esc)";
          };

          logind.settings.Login.HandleLidSwitchExternalPower = "ignore";
          tlp.enable = true;
        };
      };

    provides.repparw.includes = [ den.aspects.kanshi ];

    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.brightnessctl ];
      };
  };
}
