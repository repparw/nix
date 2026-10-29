{ inputs, pkgs }:
let
  persistence = (import ../aspects/persistence.nix { inherit inputs; }).den.aspects.persistence.nixos;
  alpha =
    (import ../aspects/alpha-persistence.nix { den = null; }).den.aspects.alpha-persistence.nixos;
  fixture = pkgs.runCommand "alpha-persistence-test-key" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    mkdir -p "$out"
    ssh-keygen -q -t ed25519 -N "" -f "$out/ssh_host_ed25519_key"
  '';
in
pkgs.testers.runNixOSTest {
  name = "alpha-btrfs-persistence";
  nodes.machine = { config, lib, ... }: {
    imports = [
      persistence
      alpha
      inputs.sops-nix.nixosModules.sops
    ];
    modules.persistence = {
      enable = true;
      mutableAccounts = true;
    };
    networking.hostName = "alpha";
    users.users.repparw.isNormalUser = true;
    virtualisation.diskImage = null;
    virtualisation.memorySize = 1536;
    virtualisation.emptyDiskImages = [ 512 ];
    # Swap uses Btrfs backing, never the volatile /.
    # qemu-vm.nix clears swapDevices by VM override; force this test's real swap unit.
    swapDevices = lib.mkForce [
      {
        device = "/persist/swapfile";
        size = 64;
      }
    ];
    virtualisation.fileSystems."/".neededForBoot = true;
    virtualisation.fileSystems."/persist" = {
      device = "/dev/disk/by-label/alpha-state";
      fsType = "btrfs";
      options = [ "subvol=@" ];
      neededForBoot = true;
      noCheck = true;
    };
    virtualisation.fileSystems."/home/containers/media/library" = {
      device = "tmpfs";
      fsType = "tmpfs";
    };
    # The VM supplies its executable store through its normal host share. This
    # exercises the backing /nix bind and database, not a standalone rescue boot.
    boot.initrd.systemd.enable = true;
    boot.supportedFilesystems = [ "btrfs" ];
    boot.initrd.systemd.storePaths = [
      pkgs.btrfs-progs
      pkgs.util-linux
      pkgs.coreutils
      fixture
    ];
    boot.initrd.systemd.services.seed-btrfs-fixture = {
      requiredBy = [ "sysroot-persist.mount" ];
      before = [ "sysroot-persist.mount" ];
      after = [ "dev-vda.device" ];
      requires = [ "dev-vda.device" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig.Type = "oneshot";
      script = ''
        if ! ${pkgs.util-linux}/bin/blkid /dev/vda; then
          ${pkgs.btrfs-progs}/bin/mkfs.btrfs -L alpha-state /dev/vda
          ${pkgs.coreutils}/bin/mkdir -p /seed
          ${pkgs.util-linux}/bin/mount -o subvolid=5 /dev/vda /seed
          ${pkgs.btrfs-progs}/bin/btrfs subvolume create /seed/@
          ${pkgs.btrfs-progs}/bin/btrfs subvolume create /seed/@home
          ${pkgs.coreutils}/bin/mkdir -p /seed/@/etc/ssh /seed/@/var/lib/nixos /seed/@/home/repparw /seed/@/nix/var/nix
          ${pkgs.coreutils}/bin/cp ${fixture}/ssh_host_ed25519_key* /seed/@/etc/ssh/
          ${pkgs.coreutils}/bin/chmod 0600 /seed/@/etc/ssh/ssh_host_ed25519_key
          echo '0123456789abcdef0123456789abcdef' > /seed/@/etc/machine-id
          echo 'root:!:1::::::' > /seed/@/etc/shadow
          echo alpha > /seed/@/.host-persistence-ready
          echo existing-home > /seed/@/home/repparw/retained
          echo wrong-home > /seed/@home/decoy
          echo existing-store-state > /seed/@/nix/var/nix/retained
          ${pkgs.btrfs-progs}/bin/btrfs filesystem mkswapfile --size 64m /seed/@/swapfile
          ${pkgs.util-linux}/bin/umount /seed
        fi
      '';
    };
    boot.initrd.systemd.mounts = [
      {
        where = "/sysroot/nix";
        what = "/sysroot/persist/nix";
        type = "none";
        options = "bind";
        requires = [ "sysroot-persist.mount" ];
        after = [ "sysroot-persist.mount" ];
        wantedBy = [ "initrd-fs.target" ];
      }
    ];
    boot.initrd.systemd.services.initrd-nixos-activation = {
      requires = [ "sysroot-nix.mount" ];
      after = [ "sysroot-nix.mount" ];
    };
    system.stateVersion = "26.05";
  };
  testScript = ''
    machine.start(allow_reboot=True)
    machine.wait_for_unit("multi-user.target")
    with subtest("Reuse the existing Btrfs root, home and store backing"):
        machine.succeed("test $(findmnt -n -o FSTYPE /) = tmpfs")
        machine.succeed("test $(findmnt -n -o FSROOT /persist) = /@")
        machine.succeed("test $(findmnt -n -o FSROOT /home) = /@/home")
        machine.succeed("grep -qx existing-home /home/repparw/retained")
        machine.succeed("test $(findmnt -n -o FSTYPE /home/containers/media/library) = tmpfs")
        machine.succeed("touch /home/containers/media/library/mounted-data")
        machine.succeed("mkdir /run/backing-check; mount -t btrfs -o subvol=@ /dev/disk/by-label/alpha-state /run/backing-check")
        machine.fail("test -e /run/backing-check/home/containers/media/library/mounted-data")
        machine.succeed("umount /run/backing-check")
        machine.fail("test -e /home/decoy")
        machine.succeed("cmp /nix/var/nix/retained /persist/nix/var/nix/retained")
        print(machine.succeed("cat /proc/swaps; systemctl list-units --all --type=swap --no-pager; grep swap /etc/fstab || true; ls -l /persist/swapfile"))
        machine.succeed("grep -Eq '^/persist/swapfile[[:space:]]' /proc/swaps")
        machine.succeed("cmp /etc/ssh/ssh_host_ed25519_key ${fixture}/ssh_host_ed25519_key")
        machine.succeed("cp /etc/shadow /persist/before-shadow")
        machine.succeed("echo test-password | passwd --stdin repparw")
        machine.succeed("! cmp -s /etc/shadow /persist/before-shadow")
        machine.succeed("cp /etc/shadow /persist/expected-shadow")
        machine.succeed("touch /ephemeral; echo after-boot >> /home/repparw/retained; sync")
    with subtest("A second tmpfs boot preserves accounts and existing data"):
        machine.reboot()
        machine.wait_for_unit("multi-user.target")
        machine.fail("test -e /ephemeral")
        machine.fail("test -e /home/containers/media/library/mounted-data")
        machine.succeed("test $(findmnt -n -o FSTYPE /home/containers/media/library) = tmpfs")
        machine.succeed("grep -qx after-boot /home/repparw/retained")
        machine.succeed("cmp /etc/shadow /persist/expected-shadow")
        machine.succeed("grep -Eq '^/persist/swapfile[[:space:]]' /proc/swaps")
        machine.succeed("cmp /nix/var/nix/retained /persist/nix/var/nix/retained")
        machine.succeed("cmp /etc/ssh/ssh_host_ed25519_key ${fixture}/ssh_host_ed25519_key")
    with subtest("An unprepared existing subvolume refuses activation"):
        machine.succeed("rm /persist/.host-persistence-ready; sync")
        machine.shutdown()
        machine.start()
        machine.wait_for_console_text("Persistence state is not prepared for this host", timeout=90)
        machine.crash()
  '';
}
