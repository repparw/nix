{
  den,
  lib,
  ...
}:
{
  den.aspects.alpha = {
    includes = [
      den.aspects.hermes-desktop
      den.aspects.monitoring._.cloud
      den.aspects.fleet-unit-state
      den.aspects.alpha._.backup
      den.aspects.btrfs-maintenance
      den.aspects.gaming
      den.aspects.logid
      den.aspects.streaming
      den.aspects.networking._.wan-ingress-shaping
      den.aspects.media-stack
      den.aspects.nixos-services._.firmware
      den.aspects.nixos-services._.coredump-watch
      den.aspects.nixos-services._.free-model-watch
      den.aspects.deploy-target
    ];

    provides.backup = {
      includes = [ den.aspects.backup ];
      nixos = { config, ... }: {
        modules.backup.exports = {
          alpha-home = {
            unit = "home-state-backup-offsite.service";
            path = "/var/lib/home-state-backup/offsite";
            pattern = ".export-complete";
          };
          jellyfin = {
            unit = "jellyfin-backup.service";
            path = config.modules.services.definitions.jellyfin.backup.path;
            pattern = "jellyfin-backup-*.zip";
          };
        }
        // lib.genAttrs [ "sonarr" "radarr" "prowlarr" "bazarr" ] (name: {
          path =
            config.modules.services.definitions.${name}.backup.path
            + lib.optionalString (name != "bazarr") "/scheduled";
          pattern = "${name}_backup_*.zip";
          maxAgeSeconds = 26 * 60 * 60;
        });
      };
    };

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
        # Staged by the prepare-home-state script (modules/scripts/) to
        # ${stateRoot}/{hdd,offsite}; see modules.backup.homeState in
        # aspects/backup.nix for the selection policy.
        stateRoot = "/var/lib/home-state-backup";
        # Each consumer has its own staging tree. A failed export never replaces
        # its previous tree.
        prepareHomeState = import ../_scripts/prepare-home-state.nix { inherit pkgs lib; } {
          inherit home stateRoot;
          paths = config.modules.backup.homeState;
          excludes = config.modules.backup.homeStateExcludes;
          criticalPaths = config.modules.backup.homeStateCritical;
          # sops/age/keys.txt deliberately HDD-only: mirror + manual, never
          # uploaded offsite.
          hddOnlyPaths = [ ".config/sops/age/keys.txt" ];
        };
      in
      {
        imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

        modules.fleet-unit-state.retainedJobs = [
          "btrfs-health-root"
          "btrfs-scrub@"
          "jellyfin-backup"
        ];

        nix.settings = {
          # Bound, not unlimited: alpha serves interactive and realtime
          # streaming workloads. Total worst-case build load is
          # max-jobs x cores ~= 6 threads; substitution is unaffected.
          max-jobs = 2;
          cores = 3;
          min-free = 100 * 1024 * 1024 * 1024;
          max-free = 130 * 1024 * 1024 * 1024;
        };

        modules.backup = {
          paths = [
            "/home/containers/backup"
            "/home/repparw/Pictures"
            "/home/repparw/Documents"
            "${stateRoot}/offsite"
          ];
          excludes = [
            "${config.users.users.repparw.home}/.config/heroic/**"
            "${config.users.users.repparw.home}/Documents/Memorias/**"
          ];
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
            ".config/Moonlight Game Streaming Project/"
            ".config/codex/config.toml"
            ".config/codex/skills/"
            ".config/codex/plugins/"
            ".config/codex/goals_1.sqlite"
            # Whole Helium profile: extension state (Vimium exclusions,
            # DeArrow, ImprovedTube) lives in per-extension LevelDB dirs that
            # would otherwise need enumerating, and update wipes have proven
            # that guessing the file list loses data. The sqlite files are
            # staged as raw copies with their sidecars, and homeStateExcludes
            # prunes caches and telemetry.
            ".config/net.imput.helium/"
            ".config/fish/fish_variables"
            ".config/mpv/watch_later"
            ".config/Raspberry Pi/Raspberry Pi Imager.conf"
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
            "Games/bbport/source/data/bbport.ini"
            "Games/bbport/source/data/user/"
            # OpenTofu state for the OCI adoption (infra/, PR-managed in Git
            # only as configuration): guarded as critical, see
            # infra/README.md. terraform.tfstate.backup is intentionally not
            # staged — restic snapshots already provide generation history.
            "Projects/nix/infra/terraform.tfstate"
          ];
          homeStateExcludes = map (dir: "/.config/net.imput.helium/${dir}") [
            "Default/History*"
            "Default/Service Worker/CacheStorage"
            "Default/Service Worker/ScriptCache"
            "Default/GPUCache"
            "Default/DawnWebGPUCache"
            "Default/DawnGraphiteCache"
            "GPUPersistentCache"
            "GrShaderCache"
            "ShaderCache"
            "GraphiteDawnCache"
            "component_crx_cache"
            "extensions_crx_cache"
            "CertificateRevocation"
            "Dictionaries"
            "segmentation_platform"
            "DeferredBrowserMetrics"
            "Variations"
          ];
          homeStateCritical = [ "Projects/nix/infra/terraform.tfstate" ];
          homeStateStagingScript = prepareHomeState;
        };

        modules.coredump-watch = {
          enable = true;
          mute = [ "wine64-preloader" ];
        };

        modules.monitoring.health.disks = [
          {
            mount = "/";
            warn = 90;
            crit = 93;
          }
          {
            mount = "/mnt/hdd";
            sleeping = true;
            warn = 98;
            crit = 99;
          }
          {
            mount = "/mnt/seagate";
            sleeping = true;
            warn = 95;
            crit = 98;
          }
        ];

        modules.monitoring.agent.extraExcludedMounts = [
          "/mnt/hdd"
          "/mnt/seagate"
          "/home/containers/media/hdd"
          "/home/containers/media/seagate"
        ];

        modules.free-model-watch.enable = true;

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
        powerManagement.cpuFreqGovernor = "powersave";

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
                    "/Games/"
                    "/Projects/"
                  ];
                };
              };
              bupstate = {
                destination = "/mnt/hdd/backup";
                sources = [
                  "${stateRoot}/hdd/.config"
                  "${stateRoot}/hdd/.local"
                  "${stateRoot}/hdd/Games"
                  # Staged OpenTofu state (Projects/nix/infra), see
                  # modules.backup.homeStateCritical.
                  "${stateRoot}/hdd/Projects"
                ];
                settings = {
                  archive = true;
                  delete = true;
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
        systemd.services.home-state-backup-offsite.serviceConfig = {
          Type = "oneshot";
          StateDirectory = "home-state-backup";
          StateDirectoryMode = "0700";
          ExecStart = "${prepareHomeState} offsite";
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

        services.resolved.settings.Resolve.DNSOverTLS = true;

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
