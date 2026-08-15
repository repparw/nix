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
      den.aspects.btrfs-maintenance
      den.aspects.gaming
      den.aspects.logid
      den.aspects.nixos-services
      den.aspects.streaming
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
          extraModprobeConfig = ''
            options netconsole netconsole=6665@192.168.0.18/eth0,6666@192.168.0.4/2c:cf:67:00:4f:47
          '';
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
          kernel.sysctl."kernel.sysrq" = 1;
          kernelModules = [ "kvm-amd" ];
          # Temporarily reproduce the intermittent shutdown hang with
          # persistent netconsole and SysRq diagnostics enabled. The previous
          # boot generation retains the known-good Linux 6.18 kernel.
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

        # The interface is not available when boot.kernelModules is processed,
        # so load netconsole only after networkd has created and configured it.
        systemd.services.netconsole-shutdown-diagnostics = {
          description = "Load netconsole for shutdown diagnostics";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig.Type = "oneshot";
          script = ''
            ${pkgs.kmod}/bin/modprobe netconsole
          '';
        };

        virtualisation.vmVariant.boot.zswap.enable = lib.mkForce false;

        fileSystems = {
          "/" = {
            device = "/dev/disk/by-uuid/51c5e80b-e22e-4d62-a3e2-ebb531deb05b";
            fsType = "btrfs";
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

        boot.kernel.sysctl."vm.swappiness" = 10;

        services = {
          udev.extraRules = ''
            # Disable USB autosuspend for Intel AX210 Bluetooth to fix sleep/wake
            ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="8087", ATTR{idProduct}=="0032", ATTR{power/control}="on"
          '';
        };

        # The WD80EAZZ ignores the ATA standby timer (hdparm -S and smartctl
        # --set standby are clamped by a vendor minimum that never engages);
        # STANDBY IMMEDIATE (hdparm -y) is the only lever. Fire it once the
        # media automounts above have idled out, so the platter actually sleeps
        # between accesses.
        systemd.services.hdd-spindown = {
          description = "Spin down media HDD when automounts are idle";
          serviceConfig.Type = "oneshot";
          script = ''
            if ${pkgs.util-linux}/bin/mountpoint -q /mnt/hdd || \
               ${pkgs.util-linux}/bin/mountpoint -q /home/containers/media/hdd; then
              exit 0
            fi
            ${pkgs.hdparm}/sbin/hdparm -y /dev/disk/by-id/ata-WDC_WD80EAZZ-00BKLB0_WD-CA2TN7HK
          '';
        };

        systemd.timers.hdd-spindown = {
          description = "Periodic media HDD spindown sweep";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*:0/5";
            Persistent = true;
          };
        };

        systemd.network = {
          links."40-eth0" = {
            matchConfig.OriginalName = "eth0";
            linkConfig.WakeOnLan = "magic";
          };
          networks = {
            "10-eth" = {
              matchConfig.Name = "eth0";
              address = [ "192.168.0.18/24" ];
              routes = [ { Gateway = "192.168.0.1"; } ];
              dns = [
                "1.1.1.1"
                "1.0.0.1"
              ];
              linkConfig.RequiredForOnline = "routable";
              extraConfig = ''
                [HierarchyTokenBucket]
                Parent=root
                Handle=1
                DefaultClass=20

                [HierarchyTokenBucketClass]
                Parent=1:0
                ClassId=1:10
                Rate=6500K
                CeilRate=6500K
                QuantumBytes=1514

                [HierarchyTokenBucketClass]
                Parent=1:0
                ClassId=1:20
                Rate=1G
                CeilRate=1G
                QuantumBytes=1514

                [CAKE]
                Parent=1:10
                Handle=10
                Bandwidth=6500K
                PriorityQueueingPreset=diffserv4

                [FairQueueingControlledDelay]
                Parent=1:20
                Handle=20
              '';
            };
            "20-wifi" = {
              matchConfig.Name = "wlan0";
              linkConfig.RequiredForOnline = "no";
              networkConfig = {
                DHCP = "yes";
                Domains = "~.";
              };
              dhcpV4Config.RouteMetric = 3000;
            };
          };
        };

        networking.firewall.interfaces.eth0 = {
          allowedTCPPorts = [
            80
            443
            54535
          ];
          allowedUDPPorts = [
            54535
          ];
        };

        networking.nftables.tables.qos = {
          family = "inet";
          content = ''
            chain classify_output {
              type route hook output priority mangle; policy accept;
              oifname "eth0" rt ip nexthop 192.168.0.1 meta priority set 1:10
            }

            chain classify_forward {
              type filter hook forward priority mangle; policy accept;
              oifname "eth0" rt ip nexthop 192.168.0.1 meta priority set 1:10
              iifname "ve-qbittorrent" oifname "eth0" rt ip nexthop 192.168.0.1 ip dscp set cs1 comment "Classify qBittorrent as CAKE bulk traffic"
            }
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
