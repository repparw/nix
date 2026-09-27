{
  den,
  lib,
  ...
}:
{
  den.aspects.alpha = {
    includes = [
      den.aspects.backup
      den.aspects.btrfs-maintenance
      den.aspects.gaming
      den.aspects.logid
      den.aspects.streaming
      den.aspects.media-stack
      den.aspects.nixos-services._.firmware
      den.aspects.nixos-services._.coredump-watch
      den.aspects.nixos-services._.disk-watch
      den.aspects.nixos-services._.reboot-watch
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
        imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

        modules.backup = {
          paths = [
            "/home/containers/backup"
            "/home/repparw/Pictures"
            "/home/repparw/Documents"
          ];
          excludes = [
            "${config.users.users.repparw.home}/.config/heroic/**"
            "${config.users.users.repparw.home}/Documents/Memorias/**"
          ];
        };

        modules.coredump-watch = {
          enable = true;
          mute = [ "wine64-preloader" ];
        };

        modules.reboot-watch.enable = true;

        modules.disk-watch = {
          enable = true;
          mounts = [
            {
              mount = "/";
              warn = 90;
              crit = 93;
            }
            {
              mount = "/mnt/hdd";
              warn = 98;
              crit = 99;
            }
            {
              mount = "/mnt/seagate";
              warn = 95;
              crit = 98;
            }
          ];
        };

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
              "x-gvfs-trash"
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
              "x-gvfs-trash"
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

          rsync = {
            enable = true;
            jobs = {
              buptohdd = {
                destination = "/mnt/hdd/backup";
                sources = [
                  "${config.users.users.repparw.home}/Pictures"
                  "${config.users.users.repparw.home}/Documents"
                ];
                settings = {
                  archive = true;
                  delete = true;
                  # Protect the allowlist jobs' output (same dest root).
                  exclude = [
                    "/.config/"
                    "/.local/"
                  ];
                };
              };
              # Explicit allowlist of irreplaceable ~/.config state. Everything
              # else is nix-declared (rebuild restores it), OAuth/session
              # (re-login), or regenerable cache. Sources use /./ with
              # --relative so the .config hierarchy is preserved under the
              # destination. delete prunes entries removed from the allowlist.
              bupconfig = {
                destination = "/mnt/hdd/backup/.config";
                sources =
                  let
                    home = config.users.users.repparw.home;
                  in
                  [
                    "${home}/./.config/sops/age/keys.txt"
                    "${home}/./.config/moonshine/"
                    "${home}/./.config/kdeconnect/"
                    "${home}/./.config/vicinae/settings.json"
                    "${home}/./.config/unity3d/"
                    "${home}/./.config/Wasteland3/"
                    "${home}/./.config/Loop_Hero/"
                    "${home}/./.config/Zelda64Recompiled/"
                    "${home}/./.config/godot/"
                    "${home}/./.config/vesktop/settings.json"
                    "${home}/./.config/vesktop/settings/"
                    "${home}/./.config/ZapZap/"
                    "${home}/./.config/Moonlight Game Streaming Project/"
                    "${home}/./.config/codex/config.toml"
                    "${home}/./.config/codex/skills/"
                    "${home}/./.config/codex/plugins/"
                    "${home}/./.config/codex/goals_1.sqlite"
                    "${home}/./.config/net.imput.helium/Default/Preferences"
                    "${home}/./.config/net.imput.helium/Default/Secure Preferences"
                    "${home}/./.config/net.imput.helium/Default/History"
                    "${home}/./.config/net.imput.helium/Default/Login Data"
                    "${home}/./.config/net.imput.helium/Default/Login Data For Account"
                    "${home}/./.config/net.imput.helium/Default/Sessions/"
                    "${home}/./.config/fish/fish_variables"
                    "${home}/./.config/mpv/watch_later"
                    "${home}/./.config/Raspberry Pi/Raspberry Pi Imager.conf"
                  ];
                settings = {
                  archive = true;
                  delete = true;
                  relative = true;
                  ignore-missing-args = true;
                };
              };
              # Vicinae keeps its state under ~/.local/share (clipboard history,
              # extensions and image cache excluded: settings + registry only).
              bupshare = {
                destination = "/mnt/hdd/backup/.local";
                sources =
                  let
                    home = config.users.users.repparw.home;
                  in
                  [
                    "${home}/./.local/share/vicinae/vicinae.db"
                    "${home}/./.local/share/vicinae/vicinae.db-shm"
                    "${home}/./.local/share/vicinae/vicinae.db-wal"
                    "${home}/./.local/share/vicinae/metadata.json"
                    "${home}/./.local/share/vicinae/script-metadata.json"
                  ];
                settings = {
                  archive = true;
                  delete = true;
                  relative = true;
                  ignore-missing-args = true;
                };
              };
              buprpi = {
                destination = "${config.modules.services.backupDir}/pi-services/";
                sources = [ "pi:services/" ];
                settings = {
                  archive = true;
                  "copy-links" = true;
                  delete = true;
                };
              };
            };
          };
        };

        # The WD80EAZZ ignores the ATA standby timer (hdparm -S and smartctl
        # --set standby are clamped by a vendor minimum that never engages);
        # STANDBY IMMEDIATE (hdparm -y) is the only lever. Guard with findmnt
        # on the LABEL; findmnt reads mountinfo and must NOT touch the
        # automount (statvfs via mountpoint would reset the idle timer).
        systemd.services.hdd-spindown = {
          description = "Spin down media HDD when automounts are idle";
          serviceConfig.Type = "oneshot";
          script = ''
            if ${pkgs.util-linux}/bin/findmnt -S /dev/disk/by-label/HDD >/dev/null 2>&1; then
              exit 0
            fi
            ${pkgs.hdparm}/sbin/hdparm -y /dev/disk/by-label/HDD
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
            54535
          ];
          allowedUDPPorts = [
            54535
          ];
        };

        networking.firewall.extraInputRules = ''
          iifname "eth0" ip saddr { ${config.modules.services.hostAddresses.pi}, ${config.modules.services.hostAddresses.epsilon} } tcp dport { 3000, 8081 } accept comment "edge ingress -> native alpha listeners"
        '';

        networking.firewall.extraForwardRules = ''
          iifname "eth0" ip saddr { ${config.modules.services.hostAddresses.pi}, ${config.modules.services.hostAddresses.epsilon} } oifname "ve-*" accept comment "edge ingress -> published container backends"
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

      };
  };

}
