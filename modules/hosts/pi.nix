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

        # Upgrade strategy C: nightly job bumps inputs, builds the next
        # closure, gates on strict local probes, pushes the bumped lock to
        # main via repparw's enrolled GitHub key, flips, soaks against
        # the probe set, and rolls back automatically if the soak fails.
        # Two consecutive rollbacks trip the breaker and pause automation;
        # pause/resume by touching /var/lib/auto-update/PAUSE, surfaced by
        # fleet-health so a paused updater never rots silently.
        systemd.services.auto-update = {
          description = "Bump inputs, build, gate, flip, and watch the result";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = with pkgs; [
            git
            nix
            nvd
            nixos-rebuild
            util-linux
            openssh
            systemd
            curl
            jq
            gawk
            gnugrep
            coreutils
            # host-update ships in repparw's per-user profile (shell aspect);
            # the flip/soak/rollback below calls it. NixOS appends /bin to
            # path entries, so the entry is the profile root.
            "/etc/profiles/per-user/repparw"
          ];
          serviceConfig = {
            Type = "oneshot";
            WorkingDirectory = "/var/lib/auto-update";
            StateDirectory = "auto-update";
            TimeoutStartSec = "90min";
          };
          # probe comes from den.aspects.nixos-services._.fleet-health
          environment.PROBE = lib.getExe config.modules.fleet-health.probe;
          script = ''
            state=/var/lib/auto-update
            api="https://discord.com/api/v10/channels/1515064288191053979/messages"
            mkdir -p "$state"

            exec 9>/run/auto-update.lock
            flock -n 9 || exit 0

            if [ -e "$state/PAUSE" ]; then
              echo "automation paused via PAUSE flag"
              exit 0
            fi

            notify() { # content
              # shellcheck disable=SC1091
              source /run/secrets/hermes-env
              curl -s -m 15 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$(jq -n --arg c "$1" '{content: $c}')" "$api" >/dev/null || true
            }

            notify_file() { # content, file
              # shellcheck disable=SC1091
              source /run/secrets/hermes-env
              curl -s -m 30 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
                -F "payload_json=$(jq -n --arg c "$1" '{content: $c}')" \
                -F "files[0]=@$2" "$api" >/dev/null || true
            }

            cd "$state"
            # Persistent clone, converged to origin/main every run: same
            # end state as a fresh clone without the re-clone cost.
            if [ -d src/.git ]; then
              git -C src fetch origin main
              git -C src reset --hard origin/main
            else
              git clone --depth 1 https://github.com/repparw/nix src
            fi
            cd src
            git remote set-url --push origin git@github.com:repparw/nix.git
            nix flake update
            if git diff --exit-code flake.lock >/dev/null; then
              echo "lock unchanged; nothing to do"
              exit 0
            fi

            free_kb() { df -k /nix | awk 'NR==2{print $4}'; }
            if [ "$(free_kb)" -lt $((10 * 1024 * 1024)) ]; then
              echo "below 10G on /nix; GCing old generations first"
              nix-collect-garbage -d >/dev/null || true
            fi
            if [ "$(free_kb)" -lt $((6 * 1024 * 1024)) ]; then
              notify ":warning: pi auto-update aborted: $(df -h /nix | awk 'NR==2{print $4}') free on /nix even after GC"
              exit 1
            fi

            if ! "$PROBE" --strict --local; then
              notify ":warning: pi auto-update aborted: local probes failing before the flip; system left untouched"
              exit 1
            fi

            # Insurance for forward-only state moves (postgres schemas):
            # best-effort fresh snapshot, never a reason to skip the flip.
            timeout 20m systemctl start restic-backups-offsite.service ||
              notify ":information_source: pi auto-update flipping without a fresh snapshot"

            nix build .#nixosConfigurations.pi.config.system.build.toplevel -o /var/lib/auto-update-result
            nvd diff /run/current-system /var/lib/auto-update-result > "$state/diff.txt" || true
            changed=$(grep -cE '^[<>] ' "$state/diff.txt" || true)
            kernel=$(grep -oE 'linux-[0-9.]+' "$state/diff.txt" | head -1 || true)

            pushed=0
            # repparw's enrolled GitHub key; root has none of its own.
            key=/home/repparw/.ssh/id_ed25519
            if [ -f "$key" ]; then
              git config user.name "pi-auto-update"
              git config user.email "pi-auto-update@repparw.com"
              git commit -m "flake.lock: Update" flake.lock
              export GIT_SSH_COMMAND="ssh -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
              # Push by URL: the clone remote is https and GIT_SSH_COMMAND
              # never applies to it.
              if git push "git@github.com:repparw/nix.git" main; then
                pushed=1
              else
                notify ":warning: pi auto-update aborted: lock push to main failed; not flipping an unpushed tree"
                exit 1
              fi
            fi

            # Flip, soak, and rollback ride the shared host-update wrapper.
            # The wrapper gates on PROBE, diffs the prebuilt
            # result, switches, and reverts on soak failure; pi stays
            # responsible for its writer duties (bump above, revert-push
            # and breaker here) and the Discord reports.
            export FLAKE="$state/src"
            host-update --yes --no-pull --result=/var/lib/auto-update-result
            rc=$?
            if [ "$rc" = 0 ]; then
              printf '0\n' > "$state/rollback-streak"
              klabel=""
              [ -n "$kernel" ] && klabel=" ($kernel)"
              notify_file "**pi flipped** — $changed packages changed$klabel" "$state/diff.txt"
            elif [ "$rc" = 3 ]; then
              printf '0\n' > "$state/rollback-streak"
              echo "lock pushed but pi closure unchanged"
            else
              streak=$(( $(cat "$state/rollback-streak" 2>/dev/null || echo 0) + 1 ))
              printf '%s\n' "$streak" > "$state/rollback-streak"
              if [ "$pushed" = 1 ]; then
                git revert --no-edit HEAD || true
                git push "git@github.com:repparw/nix.git" main || true
              fi
              note=""
              if [ "$streak" -ge 2 ]; then
                touch "$state/PAUSE"
                note=" — automation PAUSED (breaker)"
              fi
              notify ":rotating_light: pi flipped then ROLLED BACK (soak failed); $streak consecutive$note"
              notify_file "rolled-back generation's diff:" "$state/diff.txt"
              exit 1
            fi
          '';
        };

        systemd.timers.auto-update = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 04:15:00";
            Persistent = true;
            RandomizedDelaySec = "10min";
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
