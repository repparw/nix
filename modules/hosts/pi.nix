{
  den,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  den.aspects.pi = {
    includes = [
      den.batteries.hostname
      den.aspects.networking
      den.aspects.lan-hosts
      den.aspects.secrets
      # Offsite restic of every stateful dir on this host.
      den.aspects.backup
      # NOTE: do NOT include the nixos-services parent here. Its includes
      # pull the arr/jellyfin/paperless/matriz container closures (which run
      # on alpha) into pi's toplevel — ~10G on a 40G /nix that ENOSPCs on
      # every switch. Pi needs only the modules.services schema, imported
      # directly in the nixos block below, plus the sub-aspects it runs.
      den.aspects.nixos-services._.archisteamfarm
      den.aspects.nixos-services._.automations
      den.aspects.nixos-services._.homeassistant
      den.aspects.nixos-services._.fleet-health
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
        imports = [
          # modules.services schema (options/definitions) + cross-host
          # inventory.
          ../service-definitions.nix
          ../_services/inventory.nix
          ../_services/address-allocator.nix
        ];

        # Phase 2 edge cutover: the apex points at epsilon now, and the
        # home IP is static (WG endpoint + jellyfin record both hardcode
        # it), so dynamic DNS has no consumer left. ddclient ships with
        # the edge aspect; switch it off here rather than forking that.
        services.ddclient.enable = lib.mkForce false;

        # Offsite restic coverage (den.aspects.backup._.restic): container
        # configs plus the two bind-mounted user service states.
        modules.backup.paths = [
          "/home/containers/config"
          "/home/repparw/services/hass"
        ];

        # pi's repparw account: the shared base aspect plus host-specific
        # identity. The offsite restic job reads the system rclone conf, so
        # no user-level rclone wiring is needed here.
        users.users.repparw = {
          # Match the Debian-era uid so the migrated data on the NVMe
          # (/home/repparw) keeps its original ownership.
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

        # Raspberry Pi 5 (aarch64) triple-boot loader: firmware (u-boot +
        # config.txt) lives on the vfat /boot/firmware partition, while NixOS
        # writes the extlinux boot files into /boot on the ext4 root.
        #
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

        # Keep the glibc locale-archive small (~200MB vs ~1.3GB): the Pi
        # builds non-cached packages locally and disk headroom is scarce.
        # en_IE + es_AR match den.aspects.system; drop the long tail.
        i18n.supportedLocales = [
          "C.UTF-8/UTF-8"
          "en_US.UTF-8/UTF-8"
          "en_IE.UTF-8/UTF-8"
          "es_AR.UTF-8/UTF-8"
        ];

        # eMMC/SD wear: journald volatile (RAM only), weekly fstrim, and
        # reduced commit interval for SD root. /tmp already tmpfs via
        # host-common. See Steam Deck eMMC bridge docs.
        services.journald.extraConfig = "Storage=volatile\nRuntimeMaxUse=50M";
        services.fstrim.enable = true;
        zramSwap = {
          enable = true;
          algorithm = "zstd";
          memoryPercent = 25;
        };

        fileSystems = {
          # SD card (mmcblk0): flashed from the official NixOS aarch64
          # sd-image, whose dos partition table yields these PARTUUIDs.
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

          # User home + Home Assistant data live on the NVMe, so
          # ~/services/hass carries over from the Debian install unchanged.
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

          # /nix lives on the NVMe: the SD is space-constrained and upgrade
          # writes wear it.
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
          # NVMe-backed swap: the edge stack (traefik/authelia) plus HA make
          # pi the always-on host, so it needs OOM headroom beyond earlyoom.
          # NixOS creates the file automatically when `size` is set.
          {
            device = "/home/repparw/.swapfile";
            size = 8192;
          }
        ];

        hardware.bluetooth.enable = true;

        # The controller package is intentionally installed only here. Other
        # nodes are deploy-rs targets, not alternate fleet coordinators.
        environment.systemPackages = [ config.modules.fleet-update.package ];
        systemd.tmpfiles.rules = [ "d /var/lib/auto-update 0700 root root -" ];

        # Promotion and consumption are independent transactions. A failed
        # input bump therefore cannot suppress deployment of already-approved
        # main, while the shared controller lock keeps their Git/state access
        # serialized when a long promotion overlaps the consumer window.
        systemd.services.fleet-promote = {
          description = "Validate and publish a flake.lock candidate";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          restartIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
            WorkingDirectory = "/var/lib/auto-update";
            StateDirectory = "auto-update";
            TimeoutStartSec = "120min";
          };
          script = ''
            exec ${lib.getExe config.modules.fleet-update.package} \
              promote --state /var/lib/auto-update
          '';
        };

        systemd.timers.fleet-promote = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 04:15:00";
            Persistent = true;
            RandomizedDelaySec = "10min";
          };
        };

        systemd.services.fleet-deploy = {
          description = "Launch convergence on the approved main revision";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          restartIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
          };
          # The long-running worker must not be this declarative unit: pi is a
          # deployment target, and replacing the active unit from inside
          # itself can create a systemd transaction cycle. The transient unit
          # is outside the configuration being switched.
          script = ''
            if ${lib.getExe' pkgs.systemd "systemctl"} is-active --quiet fleet-deploy-run.service; then
              echo "fleet-deploy-run.service is already active"
              exit 0
            fi
            if ${lib.getExe' pkgs.systemd "systemd-run"} \
              --unit=fleet-deploy-run \
              --collect \
              --no-block \
              --property=Type=exec \
              --property=RuntimeMaxSec=180min \
              --working-directory=/var/lib/auto-update \
              ${lib.getExe config.modules.fleet-update.package} \
                deploy --wait-lock 7200 --state /var/lib/auto-update; then
              exit 0
            fi
            # The activity check and unit creation cannot be one atomic call.
            # If another launcher won that race, convergence is already owned.
            if ${lib.getExe' pkgs.systemd "systemctl"} is-active --quiet fleet-deploy-run.service; then
              echo "fleet-deploy-run.service was started concurrently"
              exit 0
            fi
            exit 1
          '';
        };

        systemd.timers.fleet-deploy = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 05:30:00";
            Persistent = true;
            RandomizedDelaySec = "10min";
          };
        };

        # Keep retries on the controller. An alpha-local service would remain
        # active while replacing its own unit and can make systemd reject the
        # activation transaction as cyclic.
        systemd.services.fleet-alpha-retry = {
          description = "Retry gated alpha fleet convergence";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          restartIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
            WorkingDirectory = "/var/lib/auto-update";
            StateDirectory = "auto-update";
            TimeoutStartSec = "240min";
          };
          script = ''
            exec ${lib.getExe config.modules.fleet-update.package} \
              deploy --host alpha --wait-lock 10800 --state /var/lib/auto-update
          '';
        };

        systemd.timers.fleet-alpha-retry = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 07:00:00";
            Persistent = true;
            RandomizedDelaySec = "15min";
          };
        };

        nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

        # The LAN DNS resolver (192.168.0.4 + 10.231.136.1) was decommissioned:
        # no LAN clients (tv/phone) or pi containers use it anymore. hass and
        # hermes resolve upstream directly; the host uses the default
        # nameservers from den.aspects.networking.
        networking = {
          # Give the nspawn containers internet access (HA integrations fetch
          # weather/HACS data) via masquerade out of eth0.
          nat = {
            enable = true;
            internalInterfaces = [ "ve-+" ];
            externalInterface = "eth0";
            # NOTE: the iifname "ve-+" rule the module renders does not match
            # these veths (observed 2026-08-23: UNREPLIED SYN_SENT conntrack
            # entries while the rule was present). The working masquerade for
            # the container subnet lives in nftables.tables.container-nat
            # below; drop this comment with the rule if the module ever fixes
            # the match.
          };

          # Masquerade container egress by source subnet. Separate table so
          # it composes with the module-rendered nixos-nat; priority 90 puts
          # it ahead of srcnat (100).
          nftables.tables.container-nat = {
            family = "ip";
            content = ''
              chain post {
                type nat hook postrouting priority 90; policy accept;
                ip saddr ${config.modules.services.bridgePrefix}.0/24 oifname "eth0" masquerade
              }
            '';
          };

          # First boot / install note: the resolver chain above only comes up
          # once this static address is configured (systemd.network below).
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

          # Containers reach the local edge by its public name (hosts file
          # points it back here), so HA's server-side OIDC calls to
          # auth.repparw.com must traverse INPUT on the bridge.
          firewall.extraInputRules = ''
            iifname "ve-*" tcp dport { 80, 443 } accept comment "containers -> local edge"
          '';

          firewall.interfaces.eth0 = {
            allowedTCPPorts = [
              80
              443
            ];
            allowedUDPPorts = [
              60001
            ];
          };
        };

        # Minimal local edge for LAN HTTPS (TV): Jellyfin via pi:443 -> alpha:8096
        # External is via epsilon (CF). Keeps LAN https without cloud round-trip.
        sops.secrets.cloudflare.sopsFile = ../../secrets/proxy.sops.yaml;

        services.traefik = {
          enable = true;
          environmentFiles = [ config.sops.secrets.cloudflare.path ];
          staticConfigOptions = {
            entryPoints.websecure = {
              address = ":443";
              http.tls.certResolver = "cloudflare";
            };
            certificatesResolvers.cloudflare.acme = {
              email = "ubritos@gmail.com";
              storage = "/var/lib/traefik/acme.json";
              dnsChallenge = {
                provider = "cloudflare";
                resolvers = [
                  "1.1.1.1:53"
                  "1.0.0.1:53"
                ];
              };
            };
          };
          dynamicConfigOptions = {
            tls.options.default.sniStrict = true;
            http = {
              routers.jellyfin = {
                rule = "Host(`jellyfin.repparw.com`)";
                service = "jellyfin";
                tls.certResolver = "cloudflare";
              };
              services.jellyfin.loadBalancer.servers = [ { url = "http://192.168.0.18:8096"; } ];
            };
          };
        };
      };
  };

  # Headless repparw on pi: the shared base account plus the rclone config
  # the offsite restic job reads. Agent tooling (t3code/opencode/mcp) comes
  # from the base aspect now; linger stays on for the user's t3code/opencode
  # services. Pi keeps the server-only t3code build; desktop hosts run the
  # full package.
  den.hosts.aarch64-linux.pi.users.repparw.aspect = {
    includes = [
      den.aspects.repparw
      den.aspects.ai._.t3code-split
    ];
  };
}
