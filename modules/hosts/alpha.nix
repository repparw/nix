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
      den.aspects.desktop
      den.aspects.gaming
      den.aspects.logid
      den.aspects.nixos-services
      den.aspects.nixos-services._.firmware
      den.aspects.nixos-services._.coredump-watch
      den.aspects.streaming
      den.aspects.streaming._.pulse-crash-fix
      den.aspects.deploy-target
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
          ../_services/address-allocator.nix
        ];

        # Offsite restic coverage. The gdrive-backed repo is deliberate:
        # the union's consumer legs cannot hold 35G of Documents (tab.digital
        # sat at 507 for weeks). Raw/Memorias are excluded — owner-managed.
        # .config is deliberately absent: Firefox sync covers the browser,
        # and the rest is cache or regenerating state.
        modules.backup.paths = [
          "/home/containers/backup"
          "/home/repparw/Pictures"
          "/home/repparw/Documents"
        ];

        # Crash capture: surface new coredumps to Discord. Only alpha runs
        # this — pi's volatile journal cannot retain coredumps. wine64-
        # preloader is routine proton breakage; adjust as tolerance changes.
        modules.coredump-watch = {
          enable = true;
          mute = [ "wine64-preloader" ];
        };

        # The desktop layer's user-facing groups (the desktop aspect itself
        # is user-agnostic).
        users.users.repparw.extraGroups = [
          "adbusers"
          "gamemode"
          "render"
          "video"
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

          zswap.enable = true;
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
        # between accesses. Guard with findmnt on the PARTITION (the fs mounts
        # /dev/sda1, so the whole-disk by-id never matches); findmnt reads
        # mountinfo and must NOT touch the automount (statvfs via mountpoint
        # would reset the idle timer).
        systemd.services.hdd-spindown = {
          description = "Spin down media HDD when automounts are idle";
          serviceConfig.Type = "oneshot";
          script = ''
            if ${pkgs.util-linux}/bin/findmnt -S /dev/disk/by-id/ata-WDC_WD80EAZZ-00BKLB0_WD-CA2TN7HK-part1 >/dev/null 2>&1; then
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
          # No :80/:443 here. Only the published service backends are
          # exposed, and only to the edge hosts that front them: pi (LAN)
          # and epsilon (public, over the tunnel).
          allowedTCPPorts = [
            54535
          ];
          allowedUDPPorts = [
            54535
          ];
        };

        networking.firewall.extraInputRules = ''
          iifname "eth0" ip saddr { 192.168.0.4, 10.5.5.3 } tcp dport { 3000, 8081 } accept comment "edge ingress -> native alpha listeners"
        '';

        # Published container backends arrive as forwarded traffic (DNAT into
        # the ve-* veth by nspawn), so they need forward-chain acceptance, not
        # input.
        networking.firewall.extraForwardRules = ''
          iifname "eth0" ip saddr { 192.168.0.4, 10.5.5.3 } oifname "ve-*" accept comment "edge ingress -> published container backends"
        '';

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

        # Consumer retry: alpha never writes flake.lock. The shared updater
        # pulls main, defers while the desktop is active, and converges this
        # node through deploy-rs if pi's staged run could not reach it.
        systemd.services.alpha-auto-update = {
          description = "Converge idle alpha through deploy-rs";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          restartIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
            WorkingDirectory = "/var/lib/alpha-auto-update";
            StateDirectory = "alpha-auto-update";
            TimeoutStartSec = "90min";
          };
          script = ''
            exec ${lib.getExe config.modules.fleet-update.package} \
              --host alpha --state /var/lib/alpha-auto-update
          '';
        };

        systemd.timers.alpha-auto-update = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 05:30:00";
            Persistent = true;
            RandomizedDelaySec = "15min";
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

  den.hosts.x86_64-linux.alpha.users.repparw.aspect = den.aspects.repparw-desktop;
}
