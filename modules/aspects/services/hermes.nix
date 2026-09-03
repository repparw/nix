{
  inputs,
  ...
}:
{
  den.aspects.nixos-services.provides.hermes = {
    nixos = { config, lib, ... }: {
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
        sopsFile = ../../../secrets/hermes.sops.yaml;
        uid = 327680;
      };

      containers.hermes = {
        autoStart = true;
        privateNetwork = true;
        hostAddress = lib.mkDefault "10.231.136.1";
        localAddress = lib.mkDefault "10.231.136.3";

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
        # privateUsers = 327680;  # DISABLED: breaks bind mounts on epsilon systemd-nspawn

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
          "--drop-capability=CAP_SYS_PTRACE,CAP_SYS_MODULE,CAP_SYS_RAWIO,CAP_MKNOD,CAP_AUDIT_READ,CAP_AUDIT_WRITE,CAP_AUDIT_CONTROL,CAP_LINUX_IMMUTABLE,CAP_SYS_BOOT,CAP_SYS_TIME,CAP_SYS_PACCT,CAP_SYS_NICE,CAP_SYS_RESOURCE,CAP_LEASE,CAP_WAKE_ALARM,CAP_BLOCK_SUSPEND,CAP_BPF,CAP_PERFMON,CAP_MAC_ADMIN,CAP_MAC_OVERRIDE"

          # nspawn already applies a syscall *allow* list; this trims groups
          # no NixOS container init needs. @privileged from the original
          # wishlist was omitted deliberately: it expands to @chown @clock
          # @module @raw-io @reboot @swap, and subtracting @chown breaks the
          # in-container activation/tmpfiles chown calls at boot.
          #
          # DISABLED 2026-08-23: the containers module ships extraFlags via
          # EXTRA_NSPAWN_FLAGS, which the start wrapper word-splits — a
          # multi-word flag like this one shatters into positional args and
          # nspawn execs "@debug" as the container init. User namespace +
          # capability drop already contain container root; restore only if
          # the module ever ships extraFlags as a proper argv array.
          # "--system-call-filter=~@obsolete @debug @swap @reboot @module @raw-io @cpu-emulation"

          # Static veth addressing (no DHCP client), so AF_PACKET is not
          # needed; netlink stays for the container's networkd/udev.
          # One family per flag: the EXTRA_NSPAWN_FLAGS env var word-splits,
          # and --restrict-address-families rejects comma lists.
          "--restrict-address-families=AF_UNIX"
          "--restrict-address-families=AF_INET"
          "--restrict-address-families=AF_INET6"
          "--restrict-address-families=AF_NETLINK"
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

            # Same resolver workaround as the HA container: nspawn breaks
            # the host-resolved loopback stub.
            networking.useHostResolvConf = false;
            networking.nameservers = [ "10.231.137.1" ];
            # nspawn seeds /etc/resolv.conf with the HOST stub pointer
            # (127.0.0.53), but nothing inside serves it unless we run our
            # own resolved forwarding to the LAN resolver above.
            services.resolved.enable = true;

            services.hermes-agent = {
              enable = true;
              # Lean gateway variant (core + Discord/Telegram/Slack
              # adapters, ~33MB vs ~700MB closure). It is exactly the
              # derivation upstream CI builds and publishes to their cachix,
              # so pi downloads instead of building.
              package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
              environmentFiles = [ "/run/secrets/hermes-env" ];
              settings.model = {
                provider = "opencode-go";
                default = "glm-5.3-flash";
              };
              settings.fallback_providers = [
                {
                  provider = "nous";
                  model = "stepfun/step-3.7-flash:free";
                }
              ];
              # Free tier: the credits gauge is pure noise in chat.
              settings.display.credits_notices = false;
              # Home channel for cron results and cross-platform pokes
              # (matches /sethome in #notifications).
              settings.platforms.discord = {
                enabled = true;
                home_channel = {
                  platform = "discord";
                  chat_id = "1515064288191053979";
                  name = "notifications";
                };
              };
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

      # Cap an unattended agent loop so it cannot starve the Pi: applied on
      # the host-side container@ unit, whose cgroup contains the whole
      # machine (systemd.nspawn's [Exec] has no MemoryMax/TasksMax keys).
      systemd.services."container@hermes".serviceConfig = {
        MemoryMax = "2G";
        TasksMax = 512;
      };

      # Egress monitoring for the hermes agent container (phase 1:
      # observe, not enforce — chain policy stays accept). Watch
      # `journalctl -k | grep hermes-egress-new` and the counters, then
      # promote to an allowlist: named sets of permitted endpoints plus a
      # default drop for the hermes container. The RFC1918 block also
      # covers sibling containers on the shared bridge as SSRF containment
      # for the agent.
      networking.nftables.tables.hermes-monitor = {
        family = "inet";
        # No sets yet; phase 2 adds allowed-endpoint sets here.
        content = ''
                      chain forward {
                        type filter hook forward priority filter; policy accept;

          # DNS to the host resolver is always allowed.
                      ip saddr ${config.containers.hermes.localAddress} ip daddr ${config.containers.hermes.hostAddress} meta l4proto { tcp, udp } th dport 53 counter accept

                      # Block LAN/internal SSRF targets from the agent container
                      # (log+drop), except the DNS rule above. Covers RFC1918 +
                      # link-local + loopback.
                      ip saddr ${config.containers.hermes.localAddress} ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 127.0.0.0/8 } counter log prefix "hermes-egress-block: " drop

                      # Monitor everything else outbound: log first packet of each new flow.
                      ip saddr ${config.containers.hermes.localAddress} ct state new counter log prefix "hermes-egress-new: " accept
                      }
        '';
      };
    };
  };
}
