{ inputs, ... }:
{
  flake-file.inputs.impermanence = {
    url = "github:nix-community/impermanence";
    flake = false;
  };

  # This aspect records the first, deliberately conservative persistence set.
  # Hosts still need a migrated /persist volume and a separate root-layout
  # change before enabling it. Merely including the aspect moves no data.
  den.aspects.persistence.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.modules.persistence;
    in
    {
      imports = [ (inputs.impermanence + "/nixos.nix") ];

      options.modules.persistence.enable = lib.mkEnableOption "the prepared host persistence mounts";
      options.modules.persistence.mutableAccounts = lib.mkEnableOption "whole-/etc persistence for mutable account files";

      config = {
        assertions = [
          {
            assertion = !cfg.enable || (config.fileSystems."/persist".neededForBoot or false);
            message = "Host persistence requires a migrated /persist filesystem with neededForBoot = true; see docs/runbooks/host-persistence.md.";
          }
          {
            assertion = !cfg.enable || !config.users.mutableUsers || cfg.mutableAccounts;
            message = "Mutable passwords require modules.persistence.mutableAccounts = true, which retains all of /etc. Review this explicit tradeoff before enabling persistence.";
          }
        ];

        environment.persistence."/persist" = {
          enable = cfg.enable;
          hideMounts = true;
          directories = [
            # passwd/PAM and NixOS atomically replace account files. Individual
            # shadow binds/symlinks do not survive those updates (upstream #120).
            # Keep the directory for the first migration, before user activation.
            (if cfg.mutableAccounts then "/etc" else "/etc/ssh")
            "/var/lib/nixos"
            # Keep existing container roots until each service has passed
            # an independent ephemeral-container restart/restore test.
            "/var/lib/nixos-containers"
            "/var/lib/systemd/timers"
            {
              directory = "/root";
              mode = "0700";
            }
            {
              directory = "/var/lib/fail2ban";
              mode = "0750";
            }
          ]
          ++ lib.optionals (config.modules.backup.hostRecovery.enable or false) [
            {
              directory = "/var/lib/host-recovery";
              mode = "0700";
            }
          ]
          ++ lib.optionals config.services.timesyncd.enable [
            {
              directory = "/var/lib/systemd/timesync";
              user = "systemd-timesync";
              group = "systemd-timesync";
            }
          ]
          ++ lib.optionals config.services.traefik.enable [
            {
              directory = "/var/lib/traefik";
              user = "traefik";
              group = config.users.users.traefik.group;
              mode = "0700";
            }
          ];
          files = lib.optional (!cfg.mutableAccounts) "/etc/machine-id" ++ [
            {
              file = "/var/lib/systemd/random-seed";
              method = "symlink";
            }
          ];
        };

        # User-password secrets must decrypt before users are created. Read
        # the key from the early backing mount instead of waiting for /etc/ssh.
        sops.age.sshKeyPaths = lib.mkIf cfg.enable (
          lib.mkForce [ "/persist/etc/ssh/ssh_host_ed25519_key" ]
        );
        fileSystems."/".neededForBoot = lib.mkIf cfg.enable true;
        # A filesystem declaration alone cannot prove migration happened. Refuse
        # an empty/wrong backing volume before activation can initialize state.
        boot.initrd.systemd.services.check-persistence-state = lib.mkIf cfg.enable {
          requiredBy = [ "initrd-nixos-activation.service" ];
          before = [ "initrd-nixos-activation.service" ];
          after = [ "sysroot-persist.mount" ];
          requires = [ "sysroot-persist.mount" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig.Type = "oneshot";
          script = ''
            if ! test -s /sysroot/persist/etc/machine-id \
              || ! test -s /sysroot/persist/etc/ssh/ssh_host_ed25519_key \
              || ! test -d /sysroot/persist/var/lib/nixos \
              || ! test -f /sysroot/persist/.host-persistence-ready \
              || ! test "$(${pkgs.coreutils}/bin/cat /sysroot/persist/.host-persistence-ready)" = ${lib.escapeShellArg config.networking.hostName} \
              ${lib.optionalString cfg.mutableAccounts "|| ! test -s /sysroot/persist/etc/shadow"}; then
              echo 'Persistence state is not prepared for this host; refusing activation.' >&2
              exit 1
            fi
          '';
        };
        boot.initrd.systemd.services.initrd-nixos-activation = lib.mkIf cfg.enable {
          requires = [
            "sysroot-var-lib-nixos.mount"
          ]
          ++ lib.optional cfg.mutableAccounts "sysroot-etc.mount";
          after = [ "sysroot-var-lib-nixos.mount" ] ++ lib.optional cfg.mutableAccounts "sysroot-etc.mount";
        };
      };
    };
}
