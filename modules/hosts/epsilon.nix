{
  den,
  lib,
  ...
}:
{
  den.aspects.epsilon = {
    includes = [
      den.batteries.hostname
      den.aspects.networking
      # den.aspects.nix (in den.default) declares sops.secrets.accessTokens;
      # without the secrets aspect the sops-nix module is missing entirely.
      den.aspects.secrets
    ];

    nixos =
      { ... }:
      {
        # Oracle Cloud Always Free A1 (VM.Standard.A1.Flex, aarch64, sa-santiago-1).
        # Installed in place via nixos-infect on top of Ubuntu's partition
        # layout: ext4 root on sda1, UEFI ESP on sda15 mounted /boot/efi.
        # The removable GRUB entry needs no NVRAM writes, which OCI VMs
        # do not persist across stop/start.
        boot.loader = {
          efi.efiSysMountPoint = "/boot/efi";
          grub = {
            enable = true;
            efiSupport = true;
            efiInstallAsRemovable = true;
            device = "nodev";
          };
        };
        boot.initrd.availableKernelModules = [
          "virtio_scsi"
          "virtio_pci"
          "virtio_blk"
        ];

        fileSystems = {
          "/" = {
            device = "/dev/disk/by-partuuid/daa9a574-99f0-449e-b43a-463650870efb";
            fsType = "ext4";
          };

          "/boot/efi" = {
            device = "/dev/disk/by-uuid/4DD2-903D";
            fsType = "vfat";
          };
        };

        zramSwap.enable = true;

        # den.aspects.networking disables predictable interface names, so the
        # virtio NIC answers as eth0; OCI hands out everything via DHCP.
        networking.interfaces.eth0.useDHCP = true;

        # Public VPS: no mosh UDP range exposed.
        programs.mosh.openFirewall = lib.mkForce false;

        # Rescue path: root keeps key access with the same shared keys.
        users.users.root.openssh.authorizedKeys.keys = import ../../authorized-keys.nix;
      };
  };

  # Headless repparw on epsilon: same base account as pi, which carries the
  # authorized keys for alpha and pi access.
  den.hosts.aarch64-linux.epsilon.users.repparw.aspect = den.aspects.repparw;
}
