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
    ];

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
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

        # Home Assistant in nspawn; trial validated 2026-08-22, replacing the
        # earlier rootless-podman quadlet pod (removed together with its
        # hostPort-80 bind when Traefik took over ingress).
        containers.homeassistant = {
          autoStart = true;
          privateNetwork = true;
          hostAddress = "10.231.136.1";
          localAddress = "10.231.136.2";
          bindMounts."/var/lib/hass" = {
            hostPath = "/home/repparw/services/hass";
            isReadOnly = false;
          };
          config =
            { ... }:
            {
              # nspawn breaks host-resolved (loopback stub); use the pi's own
              # LAN resolver over the bridge.
              networking.useHostResolvConf = false;
              networking.nameservers = [ "192.168.0.4" ];

              services.home-assistant = {
                enable = true;
                configDir = "/var/lib/hass";
                extraComponents = [
                  "default_config"
                  "wake_on_lan"
                  "google_assistant"
                  "met"
                  "radio_browser"
                  "google_translate"
                  # discovered from the migrated instance's entity registry
                  "tuya"
                  "webostv"
                  "wled"
                  "workday"
                  "google_drive"
                ];
                extraPackages =
                  ps: with ps; [
                    aiogithubapi # hacs
                    aiofiles
                    jinja2
                    joserfc # auth_oidc
                    anthropic
                    litellm
                    pyyaml # ai_automation_suggester
                  ];
              };
              networking.firewall.allowedTCPPorts = [ 8123 ];
              system.stateVersion = "26.05";
            };
        };

        # Hermes Agent gateway in its own nspawn container, mirroring the HA
        # container above. Written inline for the same reason: mkContainer
        # hardcodes alpha's resolver, which is broken on pi.
        #
        # Gateway-only by choice: it talks outbound to chat platforms, nothing
        # listens publicly, and there is no ingress vhost.
        users.groups.hermes.gid = 345;
        users.users.repparw.extraGroups = [ "hermes" ];

        # Merged into the container's $HERMES_HOME/.env at activation. Seed
        # values with: sops secrets/hermes.sops.yaml
        #
        # uid 327680 (not the default root): with the container's user
        # namespace (privateUsers below), host uid 327680 maps to container
        # root, so only container-root can read this file. The hermes-agent
        # activation script runs as container root and merges it into
        # $HERMES_HOME/.env (0640 hermes:hermes) — the service itself never
        # reads the bind mount. sops-nix's `owner` option takes a username,
        # not a number; `uid` is the numeric variant and applies even though
        # no host user has that id.
        sops.secrets."hermes-env" = {
          sopsFile = ../../secrets/hermes.sops.yaml;
          uid = 327680;
        };

        containers.hermes = {
          autoStart = true;
          privateNetwork = true;
          hostAddress = "10.231.136.1";
          localAddress = "10.231.136.3";

          # User namespace: container uid 0 -> host 327680 (= 5 x 65536,
          # systemd's upper-16-bit recommendation). Deterministic instead of
          # `pick` so the sops secret ownership above and the state dir below
          # can be pinned to the mapping. Container hermes (345) becomes host
          # 328025. Using the module option (not raw extraConfig) so nspawn
          # also gets the `:idmap` bind-mount flag for /nix — without it the
          # store would show up as nobody:nogroup inside the container.
          #
          # ONE-TIME MIGRATION: existing files in /home/repparw/services/hermes
          # must be chowned once on the host:
          #   sudo chown -R 328025:328025 /home/repparw/services/hermes
          # or the container-side hermes user cannot write them; files created
          # by the container appear on the host as 328025. The buprpi rsync
          # backup as repparw keeps working while those files stay
          # other-readable.
          privateUsers = 327680;

          # Capability drop for an agent container that only needs to talk to
          # chat platforms over the veth. Kept (container init needs them):
          # CHOWN/FOWNER/FSETID/DAC_OVERRIDE/DAC_READ_SEARCH (NixOS activation
          # + tmpfiles), SETUID/SETGID/SETPCAP/SYS_CHROOT/KILL (multi-user),
          # NET_ADMIN (veth-side interface config), NET_BIND_SERVICE/NET_RAW
          # (outbound platform APIs, ping). Dropped: CAP_SYS_ADMIN is kept
          # despite being dangerous because the upstream hermes-agent unit's
          # own hardening (ProtectSystem=strict, ReadWritePaths, PrivateTmp)
          # requires PID1 to set up mount namespaces; with the user namespace
          # it cannot reach host mounts anyway. Everything else is kernel or
          # audit machinery a gateway has no business touching: SYS_PTRACE/
          # SYS_MODULE/SYS_RAWIO/SYS_BOOT/SYS_TIME/SYS_PACCT/SYS_NICE/
          # SYS_RESOURCE/AUDIT_READ/AUDIT_WRITE/AUDIT_CONTROL/LINUX_IMMUTABLE/
          # LEASE/WAKE_ALARM/BLOCK_SUSPEND/BPF/PERFMON/MAC_ADMIN/MAC_OVERRIDE;
          # MKNOD is useless under DevicePolicy=closed and blocked in userns.
          #
          # The containers module has no [Exec]-style option for these, so
          # they go through the raw nspawn flags (extraFlags).
          extraFlags = [
            "--drop-capability=CAP_SYS_PTRACE CAP_SYS_MODULE CAP_SYS_RAWIO CAP_MKNOD CAP_AUDIT_READ CAP_AUDIT_WRITE CAP_AUDIT_CONTROL CAP_LINUX_IMMUTABLE CAP_SYS_BOOT CAP_SYS_TIME CAP_SYS_PACCT CAP_SYS_NICE CAP_SYS_RESOURCE CAP_LEASE CAP_WAKE_ALARM CAP_BLOCK_SUSPEND CAP_BPF CAP_PERFMON CAP_MAC_ADMIN CAP_MAC_OVERRIDE"

            # nspawn already applies a syscall *allow* list; this trims groups
            # no NixOS container init needs. @privileged from the original
            # wishlist was omitted deliberately: it expands to @chown @clock
            # @module @raw-io @reboot @swap, and subtracting @chown breaks the
            # in-container activation/tmpfiles chown calls at boot.
            "--system-call-filter=~@obsolete @debug @swap @reboot @module @raw-io @cpu-emulation"

            # Static veth addressing (no DHCP client), so AF_PACKET is not
            # needed; netlink stays for the container's networkd/udev.
            "--restrict-address-families=AF_UNIX AF_INET AF_INET6 AF_NETLINK"
          ];
          bindMounts = {
            "/var/lib/hermes" = {
              hostPath = "/home/repparw/services/hermes";
              isReadOnly = false;
            };
            # Host-decrypted secret consumed via services.hermes-agent
            # environmentFiles below.
            "/run/secrets/hermes-env" = {
              hostPath = config.sops.secrets."hermes-env".path;
              isReadOnly = true;
            };
          };
          config =
            { pkgs, ... }:
            {
              imports = [ inputs.hermes-agent.nixosModules.default ];

              # Same resolver workaround as the HA container above: nspawn
              # breaks the host-resolved loopback stub.
              networking.useHostResolvConf = false;
              networking.nameservers = [ "192.168.0.4" ];

              services.hermes-agent = {
                enable = true;
                # Lean gateway variant (core + Discord/Telegram/Slack
                # adapters, ~33MB vs ~700MB closure). It is exactly the
                # derivation upstream CI builds and publishes to their cachix,
                # so pi downloads instead of building.
                package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
                environmentFiles = [ "/run/secrets/hermes-env" ];
                # Circuit-breaker defaults upstream recommends for unattended
                # gateways: stop instead of looping tool calls forever.
                settings.tool_loop_guardrails = {
                  hard_stop_enabled = true;
                  hard_stop_after = {
                    exact_failure = 5;
                    idempotent_no_progress = 5;
                  };
                };
                extraPackages = with pkgs; [
                  ffmpeg
                  nodejs
                  ripgrep
                  # ddgs CLI for the bundled duckduckgo-search skill (free,
                  # keyless web search); no hermes variant ships it.
                  (python313.withPackages (ps: [ python313Packages.ddgs ]))
                ];
              };

              # Fixed ids matching the host-side hermes group (345) so the
              # buprpi rsync job running as repparw can read the state dir.
              # Without this the data would be unreadable on the host, like
              # hass (uid 286, drwx------).
              users.users.hermes.uid = 345;
              users.groups.hermes.gid = 345;

              system.stateVersion = "26.05";
            };
        };

        # Device policy note: the nixos-containers module already sets
        # DevicePolicy=closed with an empty allowlist (plus /dev/net/tun for
        # private-network+privateUsers), so nothing to configure here.

        # Cap an unattended agent loop so it cannot starve the Pi: applied on
        # the host-side container@ unit, whose cgroup contains the whole
        # machine (systemd.nspawn's [Exec] has no MemoryMax/TasksMax keys).
        systemd.services."container@hermes".serviceConfig = {
          MemoryMax = "2G";
          TasksMax = 512;
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

          # Egress monitoring for the hermes agent container (phase 1:
          # observe, not enforce — chain policy stays accept). Watch
          # `journalctl -k | grep hermes-egress-new` and the counters, then
          # promote to an allowlist: named sets of permitted endpoints plus a
          # default drop for 10.231.136.3. The RFC1918 block also covers
          # sibling containers (10.231.136.x, e.g. Home Assistant) as SSRF
          # containment for the agent.
          nftables.tables.hermes-monitor = {
            family = "inet";
            # No sets yet; phase 2 adds allowed-endpoint sets here.
            content = ''
              chain forward {
                type filter hook forward priority filter; policy accept;

                # DNS to the host resolver is always allowed.
                ip saddr 10.231.136.3 ip daddr 192.168.0.4 meta l4proto { tcp, udp } th dport 53 counter accept

                # Block LAN/internal SSRF targets from the agent container
                # (log+drop), except the DNS rule above. Covers RFC1918 +
                # link-local + loopback.
                ip saddr 10.231.136.3 ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 127.0.0.0/8 } counter log prefix "hermes-egress-block: " drop

                # Monitor everything else outbound: log first packet of each new flow.
                ip saddr 10.231.136.3 ct state new counter log prefix "hermes-egress-new: " accept
              }
            '';
          };
        };
      };
  };

  # Minimal headless repparw: same account as alpha but without the desktop
  # stack. Mirrors the Debian-era setup on the pi (fish shell, ssh keys).
  # The rootless-podman HA quadlet was removed when HA moved to nspawn and
  # Traefik took over ingress; linger stays on for the user's t3code/opencode
  # services.
  den.aspects.pi-repparw = {
    includes = [
      den.batteries.define-user
      den.batteries.primary-user
      (den.batteries.user-shell "fish")
      den.aspects.shell
      den.aspects.tmux
      den.aspects.git
      den.aspects.ssh
      # t3code + its opencode backend, for running agent sessions on the pi.
      # Skips dictation/speech (they need pipewire/wayland). The stylix theme
      # in ai/t3code.nix is guarded and stays inert without the style aspect.
      den.aspects.ai._.t3code
      den.aspects.ai._.t3code-title-patch
      den.aspects.ai._.t3code-split
      den.aspects.ai._.opencode
      den.aspects.ai._.mcp
    ];

    user = _: {
      linger = true;
      description = "repparw";
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

    provides.to-hosts = {
      nixos =
        { ... }:
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "hm-backup";
          };
        };
    };

    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        xdg.enable = true;
        home.preferXdgDirectories = true;
      };
  };

  den.hosts.aarch64-linux.pi.users.repparw = {
    aspect = den.aspects.pi-repparw;
  };
}
