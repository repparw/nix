{ den, ... }:
{
  den.aspects.alpha-persistence = {
    includes = [ den.aspects.persistence ];

    nixos =
      { config, lib, ... }:
      {
        assertions = [
          {
            assertion = !config.modules.persistence.enable || config.fileSystems."/".fsType == "tmpfs";
            message = "Alpha persistence requires a separately verified tmpfs-root layout; see docs/runbooks/alpha-impermanence.md.";
          }
        ];

        environment.persistence."/persist".directories = [
          "/home"
          "/var/log"
          "/var/lib/NetworkManager"
          "/var/lib/iwd"
          "/var/lib/tailscale"
          "/var/lib/bluetooth"
          "/var/lib/AccountsService"
          "/var/lib/alsa"
          "/var/lib/cups"
          "/var/lib/colord"
          "/var/lib/sddm"
          "/var/lib/fwupd"
          "/var/lib/libvirt"
          "/var/lib/qemu"
          "/var/lib/waydroid"
          "/var/lib/private"
          "/var/lib/credential-remediation"
          "/var/lib/alpha-auto-update"
          "/var/lib/fleet-verify"
          "/var/lib/host-recovery"
          "/var/lib/home-state-backup"
          "/var/lib/btrfs"
          "/var/lib/btrfs-health-root"
          "/var/lib/systemd/rfkill"
        ];

        # The initial backing layout reuses the live @ subvolume. A seed
        # symlink installed before the tmpfs boot would point back at itself.
        environment.persistence."/persist".files = lib.mkForce [ ];
      };
  };
}
