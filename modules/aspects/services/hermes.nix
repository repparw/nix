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

        # sops-nix's `owner` option takes a username, not a number; `uid`
        # is the numeric variant and applies even though no host user has that id.
        sops.secrets."hermes-env" = {
          sopsFile = ../../../secrets/hermes.sops.yaml;
          uid = 327680;
        };

        containers.hermes = servicesLib.mkContainer {
          inherit cfg;
          name = "hermes";
          imports = [ inputs.hermes-agent.nixosModules.default ];

          privateUsers = 327680;

          extraFlags = [
            "--drop-capability=CAP_SYS_PTRACE,CAP_SYS_MODULE,CAP_SYS_RAWIO,CAP_MKNOD,CAP_AUDIT_READ,CAP_AUDIT_WRITE,CAP_AUDIT_CONTROL,CAP_LINUX_IMMUTABLE,CAP_SYS_BOOT,CAP_SYS_TIME,CAP_SYS_PACCT,CAP_SYS_NICE,CAP_SYS_RESOURCE,CAP_LEASE,CAP_WAKE_ALARM,CAP_BLOCK_SUSPEND,CAP_BPF,CAP_PERFMON,CAP_MAC_ADMIN,CAP_MAC_OVERRIDE"

            # EXTRA_NSPAWN_FLAGS word-splits; a multi-word flag shatters
            # into positional args and nspawn execs "@debug" as init.
            # One family per flag: --restrict-address-families rejects comma lists.
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
            "/run/secrets/hermes-env" = {
              hostPath = config.sops.secrets."hermes-env".path;
              isReadOnly = true;
            };
          };
          extraConfig =
            { pkgs, ... }:
            {
              services.resolved.enable = true;

              services.hermes-agent = {
                enable = true;
                package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
                environmentFiles = [ "/run/secrets/hermes-env" ];
                settings.model = {
                  provider = "nous";
                  default = "meituan/longcat-2.0:free";
                };
                settings.fallback_providers = [
                  {
                    provider = "nous";
                    model = "stepfun/step-3.7-flash:free";
                  }
                  {
                    # authFile is store-path typed, so it cannot point
                    # at a /run/secrets runtime path without leaking the token
                    # into the Nix store.
                    provider = "openai-codex";
                    model = "gpt-5.6-sol";
                  }
                ];
                settings.reasoning_overrides."gpt-5.6-sol" = "medium";
                  settings.display.credits_notices = false;
                  settings.platforms.discord = {
                  enabled = true;
                  home_channel = {
                    platform = "discord";
                    chat_id = config.modules.services.discordChannelId;
                    name = "notifications";
                  };
                };
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
                  (python313.withPackages (ps: [ python313Packages.ddgs ]))
                ];
              };

              users.users.hermes.uid = 345;
              users.groups.hermes.gid = 345;

              system.stateVersion = "26.05";
            };
        };

        # systemd.nspawn's [Exec] has no MemoryMax/TasksMax keys.
        systemd.services."container@hermes".serviceConfig = {
          MemoryMax = "2G";
          TasksMax = 512;
        };

        networking.nftables.tables.hermes-monitor = {
          family = "inet";
          content = ''
            chain forward {
              type filter hook forward priority filter; policy accept;

              ip saddr ${config.containers.hermes.localAddress} ip daddr ${config.containers.hermes.hostAddress} meta l4proto { tcp, udp } th dport 53 counter accept
              ip saddr ${config.containers.hermes.localAddress} ip daddr 192.168.0.0/24 counter accept

              ip saddr ${config.containers.hermes.localAddress} ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 127.0.0.0/8 } counter log prefix "hermes-egress-block: " drop

              ip saddr ${config.containers.hermes.localAddress} ct state new counter log prefix "hermes-egress-new: " accept
            }
          '';
        };
      };
  };
}
