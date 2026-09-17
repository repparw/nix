{ den, ... }:
{
  den.aspects.scheduled-reboot = {
    nixos =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
        cfg = config.modules.scheduled-reboot;
      in
      {
        options.modules.scheduled-reboot = {
          enable = lib.mkEnableOption "gated reboot into a pending generation (headless hosts)";

          onCalendar = lib.mkOption {
            type = lib.types.str;
            default = "*-*-* 03:30:00";
            example = "*-*-* 03:00:00";
            description = "systemd OnCalendar for the gated reboot check. Stagger headless hosts so both edges are never down together.";
          };
        };

        config = lib.mkIf cfg.enable {
          # Same comparison as system.autoUpgrade.allowReboot: reboot only
          # when the staged system differs in kernel, kernel modules, or
          # initrd from what is currently booted. Anything else was
          # already converged by deploy-rs' switch.
          systemd.services.scheduled-reboot = {
            description = "Reboot into the staged generation when the kernel/initrd changed";
            serviceConfig.Type = "oneshot";
            path = with pkgs; [
              coreutils
              systemd
              util-linux
            ];
            script = ''
              # Never reboot mid-fleet-run: the pi controller serializes
              # promotion and deployment on this lock, and epsilon shares
              # the path harmlessly (no other locker there).
              if ! flock -n /run/fleet-update.lock true 2>/dev/null; then
                echo "scheduled-reboot: fleet update in progress, skipping"
                exit 0
              fi

              booted="$(readlink /run/booted-system/{initrd,kernel,kernel-modules})"
              built="$(readlink /nix/var/nix/profiles/system/{initrd,kernel,kernel-modules})"

              if [ "$booted" = "$built" ]; then
                echo "scheduled-reboot: already on the staged generation, nothing to do"
                exit 0
              fi

              echo "scheduled-reboot: kernel/initrd changed, rebooting into the staged generation"
              systemctl reboot
            '';
          };

          systemd.timers.scheduled-reboot = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = cfg.onCalendar;
              # A host powered off through the window must not reboot the
              # moment it comes back.
              Persistent = false;
            };
          };
        };
      };
  };
}
