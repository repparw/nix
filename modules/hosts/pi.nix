{
  den,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  # Hermes Agent ships its own flake (uv2nix package + NixOS module). Keep its
  # dependency closure isolated (no follows) so their tested combination
  # builds unchanged; updates ride tag bumps here.
  flake-file.inputs.hermes-agent.url = "github:NousResearch/hermes-agent/v2026.8.19";

  den.aspects.pi = {
    includes = [
      den.batteries.hostname
      den.aspects.networking
      den.aspects.lan-hosts
      den.aspects.secrets
      # Public edge (traefik/authelia/ddclient) + shared service inventory,
      # migrated off alpha so pi services survive workstation downtime.
      den.aspects.nixos-services._.edge
      # Always-on Steam card farming; alpha reboots too often for it.
      den.aspects.nixos-services._.archisteamfarm
      # Page-change watcher (issue #45); Discord webhook secret + 6h timer.
      den.aspects.nixos-services._.automations
      # Offsite restic of every stateful dir on this host.
      den.aspects.backup._.restic
      # Home Assistant + Hermes Agent nspawn containers.
      den.aspects.nixos-services._.homeassistant
      den.aspects.nixos-services._.hermes
      # 5-min fleet probes with two-strike Discord alerts.
      den.aspects.nixos-services._.fleet-health
    ];

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        # Offsite restic coverage (den.aspects.backup._.restic): container
        # configs plus the two bind-mounted user service states.
        modules.backup.paths = [
          "/home/containers/config"
          "/home/repparw/services/hass"
          "/home/repparw/services/hermes"
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
        # Kernel pinned to 6.18 LTS-line: linuxPackages_latest (7.2) does not
        # enumerate the BCM2712 PCIe/NVMe controller with the sd-image's DTBs
        # (boot hung waiting for the /nix device); 6.18.4x is proven on this
        # board. Revisit after the U-Boot NVMe work lands (issue #41).
        boot = {
          kernelPackages = pkgs.linuxPackages_6_18;
          # /nix is neededForBoot, so stage-1 must enumerate the NVMe: the
          # BCM2712 PCIe host driver is a module (PCIE_BRCMSTB=m) and without
          # it in the initrd the device never appears (90s timeout ->
          # emergency). nvme alone is not enough.
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

        fileSystems = {
          # SD card (mmcblk0): flashed from the official NixOS aarch64
          # sd-image, whose dos partition table yields these PARTUUIDs.
          "/" = {
            device = "/dev/disk/by-partuuid/2178694e-02";
            fsType = "ext4";
            options = [
              "defaults"
              "noatime"
            ];
          };

          "/boot/firmware" = {
            device = "/dev/disk/by-partuuid/2178694e-01";
            fsType = "vfat";
          };

          # User home + Home Assistant data live on the NVMe, so
          # ~/services/hass carries over from the Debian install unchanged.
          # Roles swapped 2026-08-23 (reinstall after SD death): home moved to
          # p2 (17.6G, ~3G used) so the store could take p1 (40G) — p2 had run
          # at 83% full as /nix. Pre-swap copy: alpha ~/backups/pi/
          # pi-nvme-home-pre-swap-20260823/.
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

        # Upgrade strategy B: nightly job bumps inputs, builds the new
        # closure, and posts the diff to Discord. Switching stays a human
        # command against the persisted work dir.
        systemd.services.upgrade-report = {
          description = "Build next-generation closure and report the diff";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = with pkgs; [
            git
            nvd
            (pkgs.writeShellApplication {
              name = "notify-upgrade";
              runtimeInputs = [
                curl
                jq
              ];
              text = ''
                # shellcheck disable=SC1091
                source /run/secrets/hermes-env
                curl -s -m 15 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
                  -H "Content-Type: application/json" \
                  -d "$(jq -n --arg c "$1" '{content: $c}')" \
                  "https://discord.com/api/v10/channels/1515064288191053979/messages" >/dev/null
              '';
            })
          ];
          serviceConfig = {
            Type = "oneshot";
            WorkingDirectory = "/var/lib/upgrade-report";
            RuntimeMaxSec = "4h";
          };
          script = ''
            set -eu
            mkdir -p /var/lib/upgrade-report
            cd /var/lib/upgrade-report
            rm -rf src
            git clone --depth 1 https://github.com/repparw/nix src
            cd src
            nix flake update
            if git diff --exit-code flake.lock >/dev/null; then
              echo "lock unchanged; nothing to report"
              exit 0
            fi
            nix build .#nixosConfigurations.pi.config.system.build.toplevel -o /var/lib/upgrade-result
            nvd diff /run/current-system /var/lib/upgrade-result > /var/lib/upgrade-diff.txt || true
            changed=$(grep -c '^[<>]' /var/lib/upgrade-diff.txt || true)
            kernel=$(grep -oE 'linux-[0-9.]+[^>]*' /var/lib/upgrade-diff.txt | head -1 || true)
            {
              echo "**pi: closure ready** — $changed packages changed $kernel"
              echo '```'
              head -c 1200 /var/lib/upgrade-diff.txt
              echo '```'
              echo "Flip with: \`ssh pi 'cd /var/lib/upgrade-report/src && nixos-rebuild switch --flake .#pi'\`"
            } > /tmp/report-msg
            notify-upgrade "$(cat /tmp/report-msg)"
          '';
        };

        systemd.timers.upgrade-report = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 04:15:00";
            Persistent = true;
            RandomizedDelaySec = "10min";
          };
        };

        nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

        # LAN DNS server: resolved listens on the LAN address and proxies to
        # Cloudflare/Quad9 over DoT. The extra 10.231.136.1 listener is the
        # nspawn bridge address — mkContainer points containers at it, and
        # without this they lose DNS on pi.
        services.resolved.settings.Resolve = {
          DNS = [
            "1.1.1.1#cloudflare-dns.com"
            "1.0.0.1#cloudflare-dns.com"
          ];
          FallbackDNS = [ "9.9.9.9#dns.quad9.net" ];
          DNSSEC = true;
          DNSOverTLS = true;
          Cache = true;
          DNSStubListenerExtra = [
            "192.168.0.4:53"
            "10.231.136.1:53"
          ];
        };

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
                ip saddr 10.231.136.0/24 oifname "eth0" masquerade
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
          # auth.repparw.com must traverse INPUT on the bridge. Port 8081 is
          # miniflux: sibling containers (glance's dashboard probes) monitor
          # it over the bridge rather than the host loopback.
          firewall.extraInputRules = ''
            iifname "ve-*" tcp dport { 80, 443 } accept comment "containers -> local edge"
            iifname "ve-*" tcp dport 8081 accept comment "containers -> miniflux"
          '';

          firewall.interfaces.eth0 = {
            allowedTCPPorts = [
              80
              443
              53
            ];
            allowedUDPPorts = [
              53
              60001
            ];
          };

          # Container traffic arrives on the nspawn veth, not eth0: allow its
          # DNS queries to reach the host resolver.
          firewall.interfaces."ve-*" = {
            allowedTCPPorts = [ 53 ];
            allowedUDPPorts = [ 53 ];
          };
        };
      };
  };

  # Headless repparw on pi: the shared base account plus the rclone config
  # the offsite restic job reads. Agent tooling (t3code/opencode/mcp) comes
  # from the base aspect now; linger stays on for the user's t3code/opencode
  # services.
  den.hosts.aarch64-linux.pi.users.repparw.aspect = den.aspects.repparw;
}
