{
  den,
  ...
}:
{
  den.aspects.pi = {
    includes = [
      den.aspects.managed-server
      den.aspects.pi._.backup
      den.aspects.nixos-services._.free-games-claimer
      den.aspects.nixos-services._.epic-freegames-portal
      den.aspects.nixos-services._.homeassistant
      den.aspects.nixos-services._.fleet-health
      den.aspects.nixos-services._.fleet-readiness
      den.aspects.fleet-controller
      den.aspects.pi-generation-retention
      den.aspects.lan-edge
    ];

    provides.backup = {
      includes = [
        den.aspects.host-backup
        den.aspects.pi-services-backup
      ];
      nixos = {
        modules.backup.exports.pi-services = {
          unit = "pi-services-backup.service";
          path = "/var/lib/pi-services-backup/current";
          pattern = ".pi-services-export.json";
        };
        modules.backup.paths = [ "/var/lib/pi-services-backup" ];
      };
    };

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        modules.services.epic-freegames-portal.email = "ubritos@gmail.com";

        sops.secrets.repparwPasswordHash = {
          sopsFile = ../../secrets/users-pi.sops.yaml;
          key = "repparwPasswordHash";
          neededForUsers = true;
        };

        modules.fleet-readiness.enable = true;
        modules.monitoring.health.disks = [
          {
            mount = "/persist";
            warn = 75;
            crit = 85;
          }
          {
            mount = "/nix";
            warn = 90;
            crit = 93;
          }
          {
            mount = "/home/repparw";
            warn = 90;
            crit = 93;
          }
        ];
        modules.persistence.enable = true;
        modules.persistence.mutableAccounts = true;

        # RP1's Cadence GEM (macb over PCIe) silently stalls its TX ring: a
        # TSTART doorbell write or a TCOMP completion can be lost on the PCIe
        # fabric, and the 7.3 driver's recovery re-writes the same posted
        # register. On 2026-11-07 the NETDEV WATCHDOG fired twice on eth0 and
        # the network never came back (pi went dark until a power cycle; see
        # raspberrypi/linux#7661 for the same re-fire pattern). Two userspace
        # layers, no kernel build:
        #
        # 1. prevention: TSO + scatter-gather off -- a reporter on
        #    LP #2133877 (comment 52) went 256 node-hours with zero stalls
        #    (baseline ~18). SG off is the load-bearing bit; TSO/GSO off with
        #    SG left on still hung (dtype.org). Negligible CPU cost on a 1G
        #    service box.
        # 2. recovery: the timer below bounces the link when the gateway is
        #    unreachable while the link reports up -- a link down/up resets
        #    the stalled GEM and always recovers (dtype.org; their same
        #    watchdog was the primary protection before their driver patch).
        #    Skipped while the fleet deploy controller is mid-transaction:
        #    a bounce would sever its ssh session to the host being
        #    activated.
        systemd.services.eth0-rp1-tx-mitigation = {
          description = "Disable TSO and scatter-gather on eth0 (RP1 macb TX stall mitigation)";
          after = [ "network-pre.target" ];
          before = [ "network.target" ];
          wantedBy = [ "network.target" ];
          unitConfig.ConditionPathExists = "/sys/class/net/eth0";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.ethtool}/bin/ethtool -K eth0 tso off sg off";
          };
        };

        systemd.services.eth0-rp1-recovery = {
          description = "Bounce eth0 when it stops passing traffic (RP1 macb TX stall recovery)";
          path = [
            pkgs.iproute2
            pkgs.iputils
            pkgs.util-linux
            pkgs.gawk
          ];
          serviceConfig = {
            Type = "oneshot";
            RuntimeDirectory = "eth0-rp1-recovery";
            ExecStart = pkgs.writeShellScript "eth0-rp1-recovery" ''
              set -eu
              stamp=/run/eth0-rp1-recovery/last-bounce
              if [ -e "$stamp" ]; then
                last=$(cat "$stamp" 2>/dev/null || echo 0)
                now=$(date +%s)
                if [ "$((now - last))" -lt 180 ]; then
                  exit 0
                fi
              fi
              ip -o link show eth0 | grep -q 'state UP' || exit 0
              if systemctl -q is-active fleet-deploy-run.service; then
                exit 0
              fi
              gw=$(ip -4 route show default | awk '{print $3; exit}')
              [ -n "$gw" ] || exit 0
              if ! ping -c 3 -W 2 -I eth0 "$gw" >/dev/null 2>&1; then
                logger -t rp1-recovery "gateway $gw unreachable with link up; bouncing eth0"
                ip link set eth0 down
                sleep 2
                ip link set eth0 up
                date +%s > "$stamp"
              fi
            '';
          };
        };

        systemd.timers.eth0-rp1-recovery = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "2min";
            OnUnitActiveSec = "60s";
          };
        };

        modules.backup.paths = [
          "/home/containers/config"
          "/var/lib/auto-update"
          "/var/lib/fleet-health"
          "/var/lib/bluetooth"
          "/var/lib/systemd/rfkill"
        ];

        environment.persistence."/persist".directories = [
          "/home/containers/config"
          "/var/lib/fleet-health"
          "/var/lib/systemd/rfkill"
          {
            directory = "/var/lib/auto-update";
            mode = "0700";
          }
          {
            directory = "/var/lib/bluetooth";
            mode = "0700";
          }
        ];

        users.users.repparw = {
          uid = 1000;
          hashedPasswordFile = config.sops.secrets.repparwPasswordHash.path;
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
          SystemMaxUse = "64M";
        };

        # This preserves the host's existing rule. nixos-rebuild can activate
        # arbitrary NixOS configuration, so this is root-equivalent access, not
        # a meaningful privilege boundary.
        security.sudo.extraRules = [
          {
            users = [ "repparw" ];
            commands = [
              {
                command = "/run/current-system/sw/bin/nixos-rebuild";
                options = [ "NOPASSWD" ];
              }
            ];
          }
        ];

        services.fstrim.enable = true;
        zramSwap = {
          enable = true;
          algorithm = "zstd";
          memoryPercent = 50;
        };

        fileSystems = {
          "/" = {
            device = "tmpfs";
            fsType = "tmpfs";
            options = [
              "x-initrd.mount"
              "mode=0755"
              "size=50%"
            ];
          };

          "/boot/firmware" = {
            device = "/dev/disk/by-label/FIRMWARE";
            fsType = "vfat";
          };

          "/persist" = {
            device = "/dev/disk/by-label/NIXOS_SD";
            fsType = "ext4";
            neededForBoot = true;
            options = [
              "defaults"
              "noatime"
              "commit=60"
            ];
          };

          "/boot" = {
            device = "/persist/boot";
            fsType = "none";
            options = [ "bind" ];
            depends = [ "/persist" ];
          };

          "/home/repparw" = {
            device = "/dev/disk/by-partuuid/7fd52c5b-02";
            fsType = "ext4";
            neededForBoot = config.modules.persistence.enable;
            options = [
              "defaults"
              "noatime"
            ]
            ++ lib.optional (!config.modules.persistence.enable) "nofail"
            ++ [
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

        hardware.bluetooth.enable = true;

        nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

        networking = {
          nat = {
            enable = true;
            externalInterface = "eth0";
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

          firewall.extraInputRules = ''
            iifname "ve-*" ip daddr ${config.modules.services.bridgePrefix}.1 meta l4proto { tcp, udp } th dport 53 accept comment "container DNS"
          '';
        };

        services.resolved.settings.Resolve.DNSStubListenerExtra = "0.0.0.0";
      };
  };

}
