{
  den,
  lib,
  ...
}:
{
  den.aspects.alpha = {
    includes = [
      den.aspects.fleet-unit-state
      den.aspects.backup
      den.aspects.btrfs-maintenance
      den.aspects.gaming
      den.aspects.logid
      den.aspects.streaming
      den.aspects.networking._.wan-ingress-shaping
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
      let
        home = config.users.users.repparw.home;
        # Single source of truth for small irreplaceable home state, kept on
        # HDD (rsync jobs below) and offsite (restic paths). Everything else
        # is nix-declared, OAuth/session (re-login), or regenerable cache.
        # sops/age/keys.txt deliberately excluded: HDD + manual only.
        homeState = [
          ".config/moonshine/"
          ".config/kdeconnect/"
          ".config/vicinae/settings.json"
          ".config/unity3d/"
          ".config/Wasteland3/"
          ".config/Loop_Hero/"
          ".config/Zelda64Recompiled/"
          ".config/godot/"
          ".config/vesktop/settings.json"
          ".config/vesktop/settings/"
          ".config/ZapZap/"
          ".config/Moonlight Game Streaming Project/"
          ".config/codex/config.toml"
          ".config/codex/skills/"
          ".config/codex/plugins/"
          ".config/codex/goals_1.sqlite"
          ".config/net.imput.helium/Default/Preferences"
          ".config/net.imput.helium/Default/Secure Preferences"
          ".config/net.imput.helium/Default/History"
          ".config/net.imput.helium/Default/Login Data"
          ".config/net.imput.helium/Default/Login Data For Account"
          ".config/net.imput.helium/Default/Sessions/"
          ".config/fish/fish_variables"
          ".config/mpv/watch_later"
          ".config/Raspberry Pi/Raspberry Pi Imager.conf"
          ".local/share/vicinae/vicinae.db"
          ".local/share/vicinae/metadata.json"
          ".local/share/vicinae/script-metadata.json"
          ".local/share/fish/fish_history"
          ".local/share/tmux/resurrect/"
          ".local/state/nvim/undo/"
          ".local/state/nvim/shada"
          ".local/state/nvim/file_frecency.bin"
          ".local/state/nvim/avante/"
          ".local/share/voxtype/meetings/"
          ".local/share/shadPS4/savedata/"
          ".local/share/shadPS4/keys.json"
          ".config/bbport-launcher/"
          ".local/share/bbport-test/data/bbport.ini"
          ".local/share/bbport-test/data/user/"
        ];
        homeDatabases = [
          ".config/codex/goals_1.sqlite"
          ".config/net.imput.helium/Default/History"
          ".config/net.imput.helium/Default/Login Data"
          ".config/net.imput.helium/Default/Login Data For Account"
          ".local/share/vicinae/vicinae.db"
        ];
        stateRoot = "/var/lib/home-state-backup";
        # Each consumer has its own staging tree. A failed export never replaces
        # its previous tree, and ExecStartPre/backupPrepareCommand abort the job.
        prepareHomeState = pkgs.writeShellScript "prepare-home-state" ''
          set -euo pipefail
          export PATH=${
            lib.makeBinPath [
              pkgs.coreutils
              pkgs.rsync
              pkgs.sqlite
            ]
          }
          test -d ${lib.escapeShellArg home}
          case "$1" in hdd|offsite) ;; *) exit 1 ;; esac
          destination=${stateRoot}/$1
          temporary=$(mktemp -d "${stateRoot}/.prepare-$1.XXXXXX")
          trap 'rm -rf "$temporary"' EXIT
          mkdir -p "$temporary/.config" "$temporary/.local"
          rsync --archive --relative --ignore-missing-args -- \
            ${
              lib.escapeShellArgs (
                map (p: "${home}/./${p}") (lib.filter (p: !(lib.elem p homeDatabases)) homeState)
              )
            } \
            "$temporary/"
          ${lib.concatMapStringsSep "\n" (p: ''
            if [ -f ${lib.escapeShellArg "${home}/${p}"} ]; then
              mkdir -p "$temporary/${builtins.dirOf p}"
              sqlite3 ${lib.escapeShellArg "${home}/${p}"} \
                '.timeout 10000' ".backup '$temporary/${p}'"
              chmod --reference=${lib.escapeShellArg "${home}/${p}"} "$temporary/${p}"
              chown --reference=${lib.escapeShellArg "${home}/${p}"} "$temporary/${p}"
            fi
          '') homeDatabases}
          if [ "$1" = hdd ]; then
            rsync --archive --relative --ignore-missing-args -- \
              ${lib.escapeShellArg "${home}/./.config/sops/age/keys.txt"} "$temporary/"
          fi
          rm -rf "$destination"
          mv "$temporary" "$destination"
        '';
      in
      {
        imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

        modules.fleet-unit-state.retainedJobs = [
          "btrfs-health-root"
          "btrfs-scrub@"
          "jellyfin-backup"
        ];

        modules.backup = {
          paths = [
            "/home/containers/backup"
            "/home/repparw/Pictures"
            "/home/repparw/Documents"
            "${stateRoot}/offsite/.config"
            "${stateRoot}/offsite/.local"
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
          kernelPackages = pkgs.linuxPackages_latest;
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
              # Sync complete staged subtrees: --delete now prunes removed
              # allowlist leaves and the legacy whole-.config contents too.
              bupstate = {
                destination = "/mnt/hdd/backup";
                sources = [
                  "${stateRoot}/hdd/.config"
                  "${stateRoot}/hdd/.local"
                ];
                settings = {
                  archive = true;
                  delete = true;
                };
              };
              buprpi = {
                destination = "${config.modules.services.backupDir}/pi-services/";
                sources = [
                  "repparw@${den.hosts.aarch64-linux.pi.serviceAddress}:/var/lib/pi-services-backup/current/"
                ];
                settings = {
                  archive = true;
                  "copy-links" = true;
                  "delete-after" = true;
                  "rsync-path" = "sudo -n pi-services-backup-send";
                };
              };
            };
          };
        };

        systemd.services.rsync-job-bupstate.serviceConfig = {
          StateDirectory = "home-state-backup";
          StateDirectoryMode = "0700";
          ExecStartPre = "${prepareHomeState} hdd";
        };
        systemd.services.restic-backups-offsite.serviceConfig = {
          StateDirectory = "home-state-backup";
          StateDirectoryMode = "0700";
        };
        services.restic.backups.offsite.backupPrepareCommand = "${prepareHomeState} offsite";
        # Use the account that owns the destination and has SSH access to pi.
        systemd.services.rsync-job-buprpi.serviceConfig = {
          User = lib.mkForce "repparw";
          Group = lib.mkForce config.users.users.repparw.group;
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
