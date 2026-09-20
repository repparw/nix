{
  den,
  ...
}:
{
  den.aspects.pi = {
    includes = [
      den.aspects.backup
      den.aspects.service-host
      den.aspects.nixos-services._.automations
      den.aspects.nixos-services._.homeassistant
      den.aspects.nixos-services._.fleet-health
      den.aspects.fleet-controller
      den.aspects.lan-edge
      den.aspects.deploy-target
    ];

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        modules.backup.paths = [
          "/home/containers/config"
          "/home/repparw/services/hass"
        ];

        users.users.repparw = {
          uid = 1000;
          extraGroups = [ "wheel" ];
          subUidRanges = [
            {
              startUid = 100000;
              count = 65536;
            }
          ];
          subGidRanges = [
            {
              startGid = 100000;
              count = 65536;
            }
          ];
        };

        # /nix is neededForBoot, so stage-1 must enumerate the NVMe: the
        # BCM2712 PCIe host driver is a module (PCIE_BRCMSTB=m) and without
        # it in the initrd the device never appears (90s timeout ->
        # emergency). nvme alone is not enough.
        boot = {
          kernelPackages = pkgs.linuxPackages_latest;
          initrd.availableKernelModules = [
            "pcie_brcmstb"
            "nvme"
            "mmc_block"
            "ext4"
          ];
          kernelParams = [
            "console=ttyMA0,115200n8"
            "console=tty0"
          ];
          loader = {
            grub.enable = false;
            generic-extlinux-compatible.enable = true;
          };
        };

        i18n.supportedLocales = [
          "C.UTF-8/UTF-8"
          "en_US.UTF-8/UTF-8"
          "en_IE.UTF-8/UTF-8"
          "es_AR.UTF-8/UTF-8"
        ];

        services.journald.settings.Journal = {
          Storage = "volatile";
          RuntimeMaxUse = "50M";
        };
        services.fstrim.enable = true;
        zramSwap = {
          enable = true;
          algorithm = "zstd";
          memoryPercent = 25;
        };

        fileSystems = {
          "/" = {
            device = "/dev/disk/by-partuuid/2178694e-02";
            fsType = "ext4";
            options = [
              "defaults"
              "noatime"
              "commit=60"
            ];
          };

          "/boot/firmware" = {
            device = "/dev/disk/by-partuuid/2178694e-01";
            fsType = "vfat";
          };

          "/home/repparw" = {
            device = "/dev/disk/by-partuuid/7fd52c5b-02";
            fsType = "ext4";
            options = [
              "defaults"
              "noatime"
              "nofail"
              # BCM2712 PCIe link training can take >90s on this board;
              # default device timeout aborted the boot first.
              "x-systemd.device-timeout=5min"
            ];
          };

          "/nix" = {
            device = "/dev/disk/by-partuuid/7fd52c5b-01";
            fsType = "ext4";
            options = [
              "defaults"
              "noatime"
              "x-systemd.device-timeout=5min"
            ];
          };
        };

        swapDevices = [
          {
            device = "/home/repparw/.swapfile";
            size = 8192;
          }
        ];

        hardware.bluetooth.enable = true;

        nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

        networking = {
          nat = {
            enable = true;
            internalInterfaces = [ "ve-+" ];
            externalInterface = "eth0";
            # NOTE: the iifname "ve-+" rule the module renders does not match
            # these veths (observed 2026-08-23: UNREPLIED SYN_SENT conntrack
            # entries while the rule was present). The working masquerade for
            # the container subnet lives in nftables.tables.container-nat below.
          };

          nftables.tables.container-nat = {
            family = "ip";
            content = ''
              chain post {
                type nat hook postrouting priority 90; policy accept;
                ip saddr ${config.modules.services.bridgePrefix}.0/24 oifname "eth0" masquerade
              }
            '';
          };

          interfaces.eth0.ipv4.addresses = [
            {
              address = "192.168.0.4";
              prefixLength = 24;
            }
          ];
          defaultGateway = {
            address = "192.168.0.1";
            interface = "eth0";
          };

          firewall.interfaces.eth0 = {
            allowedUDPPorts = [
              60001
            ];
          };
        };
      };
  };

}
