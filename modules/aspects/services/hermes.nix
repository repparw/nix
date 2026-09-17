{
  inputs,
  ...
}:
{
  den.aspects.nixos-services.provides.hermes = {
    service-registry = {
      name = "hermes";
      definition.container = true;
    };

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.modules.services;
        servicesLib = import ../../_services/lib.nix { inherit lib pkgs; };
      in
      {
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

        containers.hermes = servicesLib.mkContainer {
          inherit cfg;
          name = "hermes";
          imports = [ inputs.hermes-agent.nixosModules.default ];

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
          extraConfig =
            { pkgs, ... }:
            {
              # mkContainer sets useHostResolvConf = false and nameservers to
              # the bridge gateway; systemd-resolved still forwards out of the
              # container so in-container services resolve correctly.
              services.resolved.enable = true;

              services.hermes-agent = {
                enable = true;
                # Lean gateway variant (core + Discord/Telegram/Slack
                # adapters, ~33MB vs ~700MB closure). It is exactly the
                # derivation upstream CI builds and publishes to their cachix,
                # so pi downloads instead of building.
                package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
                environmentFiles = [ "/run/secrets/hermes-env" ];
                # No Go subscription right now: default to the free Nous
                # endpoint instead of opencode-go. LongCat 2.0 leads the
                # free tier on terminal-agent work (TB-2.1 70.8 /
                # SWE-Pro 59.5 / 1M ctx, 2026-09-12).
                settings.model = {
                  provider = "nous";
                  default = "meituan/longcat-2.0:free";
                };
                settings.fallback_providers = [
                  {
                    provider = "nous";
                    # Second free net with a known-good slug (was the
                    # previous fallback). Runner-up Laguna S 2.1 (TB-2.1
                    # 70.2, open-weight) if either free window closes.
                    model = "stepfun/step-3.7-flash:free";
                  }
                  {
                    # ChatGPT/Codex subscription OAuth (separate from the
                    # free Nous tier above). Credential is NOT a sops
                    # secret: `hermes auth` is interactive (browser
                    # login) and stores refreshable tokens in
                    # $HERMES_HOME/auth.json, which the upstream module
                    # deliberately leaves alone after first install.
                    # authFile is store-path typed, so it cannot point
                    # at a /run/secrets runtime path without leaking
                    # the token into the Nix store — hence no authFile
                    # here. Seed once on epsilon (as root):
                    #   sudo install -o 328025 -g 328025 -m 600 auth.json \
                    #     /home/repparw/services/hermes/.hermes/auth.json
                    # (host ids for container hermes 345, see the
                    # user-namespace comment above; .hermes = HERMES_HOME
                    # = stateDir/.hermes). Then:
                    #   sudo systemctl restart container@hermes
                    # Get auth.json from any machine with the hermes CLI:
                    # `hermes model` -> ChatGPT or Codex Subscription.
                    # Until that file exists this entry is inert: Hermes
                    # only resolves it when the Nous chain above fails.
                    # Last in the chain so the free fallbacks stay first.
                    provider = "openai-codex";
                    # Flagship tier at default effort; revisit once the
                    # gateway's real workload is known (Terra-medium is
                    # the likely cost/quality sweet spot, Luna for bulk).
                    model = "gpt-5.6-sol";
                  }
                ];
                # Pinned (not inherited): keeps the Codex fallback at
                # medium even if the global reasoning_effort moves.
                # No `hermes config set` support upstream, but the Nix
                # settings map lands in config.yaml all the same.
                settings.reasoning_overrides."gpt-5.6-sol" = "medium";
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

        # Egress monitoring and private-network SSRF containment for the
        # Hermes agent. The explicit home-LAN exception matches epsilon's
        # forwarding policy; all other private and sibling destinations fail
        # closed before public flows are logged and accepted.
        networking.nftables.tables.hermes-monitor = {
          family = "inet";
          content = ''
            chain forward {
              type filter hook forward priority filter; policy accept;

              # DNS to the host resolver and required home services.
              ip saddr ${config.containers.hermes.localAddress} ip daddr ${config.containers.hermes.hostAddress} meta l4proto { tcp, udp } th dport 53 counter accept
              ip saddr ${config.containers.hermes.localAddress} ip daddr 192.168.0.0/24 counter accept

              # Block remaining RFC1918, link-local, and loopback targets.
              ip saddr ${config.containers.hermes.localAddress} ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 127.0.0.0/8 } counter log prefix "hermes-egress-block: " drop

              # Log the first packet of every accepted public flow.
              ip saddr ${config.containers.hermes.localAddress} ct state new counter log prefix "hermes-egress-new: " accept
            }
          '';
        };
      };
  };
}
