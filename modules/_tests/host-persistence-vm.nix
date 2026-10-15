{
  inputs,
  pkgs,
}:
let
  backup = (import ../aspects/backup.nix { den = null; }).den.aspects.backup.nixos;
  persistence = (import ../aspects/persistence.nix { inherit inputs; }).den.aspects.persistence.nixos;
  # Disposable test credentials, generated in the build sandbox. No production
  # key, password or SOPS file is used by this VM.
  fixture =
    pkgs.runCommand "persistence-test-credentials"
      {
        nativeBuildInputs = [
          pkgs.openssh
          pkgs.ssh-to-age
          pkgs.sops
          pkgs.openssl
        ];
      }
      ''
        mkdir -p "$out"
        ssh-keygen -q -t ed25519 -N "" -f "$out/ssh_host_ed25519_key"
        recipient=$(ssh-to-age < "$out/ssh_host_ed25519_key.pub")
        hash=$(printf '%s' 'Bootstrap-Test-Only-4321!' | openssl passwd -6 -stdin)
        printf 'password: "%s"\n' "$hash" > secret.yaml
        sops --encrypt --age "$recipient" --input-type yaml --output-type yaml secret.yaml > "$out/secret.yaml"
      '';
  common = { config, lib, ... }: {
    imports = [
      persistence
      backup
      inputs.sops-nix.nixosModules.sops
    ];
    modules.persistence = {
      enable = true;
      mutableAccounts = true;
    };
    virtualisation.diskImage = null;
    virtualisation.memorySize = 1024;
    boot.initrd.systemd.enable = true;
    virtualisation.fileSystems."/".neededForBoot = true;
    virtualisation.fileSystems."/persist" = {
      device = "/dev/disk/by-label/persist";
      fsType = "ext4";
      neededForBoot = true;
      options = [ "x-systemd.device-timeout=10s" ];
    };
    environment.persistence."/persist".directories = [
      {
        directory = "/home/repparw";
        user = "repparw";
        group = "users";
        mode = "0700";
      }
      "/var/lib/auto-update"
      "/var/lib/test-service"
    ];
    sops.secrets.bootstrap = {
      sopsFile = "${fixture}/secret.yaml";
      key = "password";
      neededForUsers = true;
    };
    users.mutableUsers = true;
    users.users.repparw = {
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets.bootstrap.path;
    };
    services.openssh.enable = true;
    networking.hostName = "alpha";
    modules.backup.retentionArgs = [ ];
    modules.backup.exports.test-service = {
      unit = "test-service-export.service";
      path = "/var/lib/test-service/export";
      pattern = "*.db";
    };
    modules.backup.exports.zz-independent = {
      unit = "independent-export.service";
      path = "/var/lib/test-service/independent";
      pattern = "*.txt";
    };
    systemd.services.independent-export = {
      serviceConfig.Type = "oneshot";
      path = [ pkgs.coreutils ];
      script = ''
        mkdir -p /var/lib/test-service/independent
        date --iso-8601=ns > /var/lib/test-service/independent/state.txt
      '';
    };
    systemd.services.test-service-export = {
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig.Type = "oneshot";
      path = [
        pkgs.coreutils
        pkgs.sqlite
      ];
      script = ''
        test ! -e /run/export-fail
        if test -e /run/export-noop; then exit 0; fi
        mkdir -p /var/lib/test-service/export/manual
        if test -e /run/export-stale; then
          touch -d '2 days ago' /var/lib/test-service/export/manual/data.db
          exit 0
        fi
        if test -e /run/export-empty; then
          : > /var/lib/test-service/export/manual/data.db
          exit 0
        fi
        sqlite3 /var/lib/test-service/data.db ".backup '/var/lib/test-service/export/manual/data.db'"
      '';
    };
    systemd.services.restic-backups-offsite.unitConfig.StartLimitIntervalSec = 0;
    systemd.timers.restic-backups-offsite.wantedBy = lib.mkForce [ ];
    services.restic.backups.offsite = {
      repository = "/persist/test-repository";
      passwordFile = "/run/restic-password";
      initialize = true;
      timerConfig = {
        OnActiveSec = "1s";
      };
      exclude = [
        "/var/lib/test-service/data.db"
        "/var/lib/test-service/data.db-*"
      ];
      extraBackupArgs = [ "--one-file-system" ];
      paths = [
        "/etc"
        "/home/repparw"
        "/var/lib/nixos"
        "/var/lib/test-service"
        "/var/lib/auto-update"
        "/var/lib/host-recovery"
        "/var/lib/systemd/timers"
      ];
    };
    environment.systemPackages = [
      inputs.self.nixosConfigurations.alpha.config.modules.fleet-cli.package
      pkgs.sops
      pkgs.ssh-to-age
      pkgs.restic
      pkgs.sqlite
      pkgs.acl
      pkgs.attr
    ];
    system.stateVersion = "26.05";
  };
in
pkgs.testers.runNixOSTest {
  name = "host-persistence-boot-and-recovery";
  nodes = {
    machine = { config, ... }: {
      imports = [ common ];
      virtualisation.emptyDiskImages = [ 512 ];
      # Only the test's blank virtual disk is formatted. Production migration
      # must populate an existing backing filesystem separately.
      boot.initrd.systemd.storePaths = [
        pkgs.e2fsprogs
        pkgs.util-linux
        pkgs.coreutils
        fixture
      ];
      boot.initrd.systemd.services.prepare-test-disk = {
        wantedBy = [ "initrd.target" ];
        requiredBy = [ "sysroot-persist.mount" ];
        before = [ "sysroot-persist.mount" ];
        after = [ "dev-vda.device" ];
        requires = [ "dev-vda.device" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          if ! ${pkgs.util-linux}/bin/blkid /dev/vda; then
            ${pkgs.e2fsprogs}/bin/mkfs.ext4 -L persist /dev/vda
            ${pkgs.coreutils}/bin/mkdir -p /seed
            ${pkgs.util-linux}/bin/mount /dev/vda /seed
            ${pkgs.coreutils}/bin/mkdir -p /seed/etc/ssh /seed/var/lib/nixos
            ${pkgs.coreutils}/bin/cp ${fixture}/ssh_host_ed25519_key* /seed/etc/ssh/
            ${pkgs.coreutils}/bin/chmod 0600 /seed/etc/ssh/ssh_host_ed25519_key
            echo '0123456789abcdef0123456789abcdef' > /seed/etc/machine-id
            echo 'root:!:1::::::' > /seed/etc/shadow
            echo '${config.networking.hostName}' > /seed/.host-persistence-ready
            ${pkgs.util-linux}/bin/umount /seed
          fi
        '';
      };
      virtualisation.fileSystems."/persist".noCheck = true;
    };
    missing = { ... }: {
      imports = [ common ];
      # No persistent disk: account activation and application startup must fail.
    };
  };
  testScript = ''
    import os
    import subprocess

    machine.start(allow_reboot=True)
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test $(findmnt -n -o FSTYPE /) = tmpfs")
    machine.succeed("test $(findmnt -n -o FSTYPE /etc) = ext4")
    machine.succeed("test -s /run/secrets-for-users/bootstrap")
    machine.succeed("install -m 0600 /etc/machine-id /persist/expected-machine-id")
    machine.succeed("cp /etc/ssh/ssh_host_ed25519_key /persist/expected-ssh-key")
    machine.succeed("id -u repparw > /persist/expected-uid")
    machine.succeed("touch /var/lib/auto-update/PAUSE; echo state > /home/repparw/state")
    machine.succeed("sqlite3 /var/lib/test-service/data.db 'create table state(value); insert into state values (42);'")
    machine.succeed("setfattr -n user.recovery -v preserved /home/repparw/state; setfacl -m u:nobody:r /home/repparw/state")
    machine.succeed("touch /var/lib/systemd/timers/stamp-test.timer; echo ephemeral > /should-disappear")
    machine.succeed("echo legacy-checkpoint > /var/lib/host-recovery/checkpoint")

    with subtest("A real passwd update survives activation and reboot"):
        machine.succeed("printf 'Changed-Test-Only-9876!\\nChanged-Test-Only-9876!\\n' | passwd repparw")
        machine.succeed("getent shadow repparw | cut -d: -f2 > /persist/expected-password")
        machine.succeed("/run/current-system/activate")
        machine.succeed("getent shadow repparw | cut -d: -f2 > /run/actual-password; cmp -s /persist/expected-password /run/actual-password")
        machine.reboot()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("getent shadow repparw | cut -d: -f2 > /run/actual-password; cmp -s /persist/expected-password /run/actual-password")
        machine.fail("test -e /should-disappear")
        machine.succeed("cmp -s /persist/expected-machine-id /etc/machine-id; cmp -s /persist/expected-ssh-key /etc/ssh/ssh_host_ed25519_key")
        machine.succeed("id -u repparw > /run/actual-uid; cmp -s /persist/expected-uid /run/actual-uid")
        machine.succeed("test -e /var/lib/auto-update/PAUSE; test -e /var/lib/systemd/timers/stamp-test.timer")
        assert machine.succeed("sqlite3 /var/lib/test-service/data.db 'select value from state;'").strip() == "42"

    with subtest("Backup restoration preserves identity, accounts, database and file metadata"):
        machine.succeed("echo test-only-restic-password > /run/restic-password; chmod 0600 /run/restic-password")
        restic = "RESTIC_PASSWORD_FILE=/run/restic-password restic -r /persist/test-repository "
        machine.succeed("systemctl start restic-backups-offsite.timer")
        machine.wait_until_succeeds(restic + "snapshots --json | ${pkgs.jq}/bin/jq -e 'length == 1'")
        machine.succeed("systemctl stop restic-backups-offsite.timer")
        machine.wait_until_succeeds("systemctl show restic-backups-offsite.service -p ActiveState --value | grep -qx inactive")
        machine.succeed("systemctl show restic-backups-offsite.service -p Result --value | grep -qx success")
        machine.succeed("fleet backup run")
        machine.succeed(restic + "snapshots --json | ${pkgs.jq}/bin/jq -e 'length == 2'")
        snapshot = machine.succeed(restic + "snapshots --latest 1 --json | ${pkgs.jq}/bin/jq -r '.[0].id'").strip()
        machine.succeed("mkdir -m 0700 /restored")
        machine.succeed(restic + "restore --verify " + snapshot + " --target /restored")
        machine.succeed("cmp -s /etc/shadow /restored/etc/shadow; cmp -s /etc/ssh/ssh_host_ed25519_key /restored/etc/ssh/ssh_host_ed25519_key")
        machine.succeed("test $(stat -c %a /restored/etc/shadow) = $(stat -c %a /etc/shadow)")
        machine.succeed("test $(stat -c %u:%g /restored/home/repparw/state) = $(stat -c %u:%g /home/repparw/state)")
        machine.succeed("getfattr --only-values -n user.recovery /restored/home/repparw/state | grep -qx preserved")
        machine.succeed("getfacl -cp /home/repparw/state > /run/acl-before; getfacl -cp /restored/home/repparw/state > /run/acl-after; cmp -s /run/acl-before /run/acl-after")
        assert machine.succeed("sqlite3 /restored/var/lib/test-service/export/manual/data.db 'pragma integrity_check; select value from state;'").strip() == "ok\n42"

        machine.fail("test -e /restored/var/lib/test-service/data.db")
        machine.succeed("cmp -s /var/lib/host-recovery/checkpoint /restored/var/lib/host-recovery/checkpoint")
        machine.succeed("cmp -s /var/lib/auto-update/PAUSE /restored/var/lib/auto-update/PAUSE; test -e /restored/var/lib/systemd/timers/stamp-test.timer")
        machine.succeed("umask 077; ssh-to-age -private-key -i /restored/etc/ssh/ssh_host_ed25519_key > /run/restored-age-key")
        machine.succeed("SOPS_AGE_KEY_FILE=/run/restored-age-key sops --decrypt ${fixture}/secret.yaml > /dev/null")

    with subtest("Failed, unchanged, stale and empty exports upload an explicitly incomplete snapshot"):
        for count, mode in enumerate(["fail", "noop", "stale", "empty"], start=3):
            machine.succeed("touch /run/export-" + mode)
            machine.fail("fleet backup run")
            machine.succeed(restic + "snapshots --json | ${pkgs.jq}/bin/jq -e 'length == " + str(count) + "'")
            machine.succeed(restic + "dump latest /var/lib/backup-exports/offsite.json | ${pkgs.jq}/bin/jq -e '.status == \"incomplete\" and .exports[\"test-service\"].status == \"failed\"'")
            machine.succeed(restic + "dump latest /var/lib/backup-exports/offsite.json | ${pkgs.jq}/bin/jq -e '.exports[\"zz-independent\"].status == \"complete\"'")
            machine.succeed(restic + "dump latest /var/lib/test-service/independent/state.txt")
            machine.succeed("rm /run/export-" + mode)
        machine.succeed("fleet backup run alpha")
        machine.succeed(restic + "snapshots --json | ${pkgs.jq}/bin/jq -e 'length == 7'")
        machine.succeed(restic + "dump latest /var/lib/backup-exports/offsite.json | ${pkgs.jq}/bin/jq -e '.status == \"complete\"'")

    with subtest("One-file-system follows same-device binds and skips other devices unless explicit"):
        machine.succeed("mkdir -p /home/repparw/same-device /home/repparw/other-device /persist/nested-state")
        machine.succeed("echo bind-data > /persist/nested-state/state; mount --bind /persist/nested-state /home/repparw/same-device")
        machine.succeed("mount -t tmpfs tmpfs /home/repparw/other-device; echo other-data > /home/repparw/other-device/state")
        machine.succeed(restic + "backup --one-file-system /home/repparw")
        machine.succeed(restic + "restore --verify latest --target /run/parent-restore")
        machine.succeed("cmp -s /home/repparw/same-device/state /run/parent-restore/home/repparw/same-device/state")
        machine.fail("test -e /run/parent-restore/home/repparw/other-device/state")
        machine.succeed(restic + "backup --one-file-system /home/repparw /home/repparw/other-device")
        machine.succeed(restic + "restore --verify latest --target /run/explicit-restore")
        machine.succeed("cmp -s /home/repparw/other-device/state /run/explicit-restore/home/repparw/other-device/state")

    with subtest("A root reset retains persistent state and permits restoring the exported offsite payload"):
        machine.succeed("echo ephemeral > /after-backup-ephemeral; sync")
        machine.crash()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("getent shadow repparw | cut -d: -f2 > /run/actual-password; cmp -s /persist/expected-password /run/actual-password")
        machine.succeed("test -e /var/lib/auto-update/PAUSE; test -s /run/secrets-for-users/bootstrap")
        machine.fail("test -e /after-backup-ephemeral")
        machine.fail("test -e /restored")
        machine.succeed("echo test-only-restic-password > /run/restic-password; chmod 0600 /run/restic-password")
        machine.succeed("mkdir -m 0700 /restored-after-reset")
        machine.succeed(restic + "restore --verify " + snapshot + " --target /restored-after-reset")
        machine.succeed("cmp -s /etc/ssh/ssh_host_ed25519_key /restored-after-reset/etc/ssh/ssh_host_ed25519_key; cmp -s /etc/shadow /restored-after-reset/etc/shadow")
        assert machine.succeed("sqlite3 /restored-after-reset/var/lib/test-service/export/manual/data.db 'pragma integrity_check; select value from state;'").strip() == "ok\n42"
        machine.fail("test -e /restored-after-reset/var/lib/test-service/data.db")

    with subtest("Missing backing storage prevents normal boot"):
        missing.start()
        missing.wait_for_console_text("Timed out waiting for device", timeout=90)
        missing.wait_for_console_text("Dependency failed", timeout=30)
        missing.crash()

    with subtest("An unprepared volume fails before activation and can be rescued offline"):
        machine.succeed("mv /persist/.host-persistence-ready /persist/.host-persistence-ready.saved; sync")
        machine.shutdown()
        machine.start()
        machine.wait_for_console_text("Persistence state is not prepared for this host", timeout=90)
        machine.crash()
        disk = machine.state_dir / "empty0.qcow2"
        raw = machine.state_dir / "rescue.raw"
        repaired = machine.state_dir / "repaired.qcow2"
        subprocess.run(["${pkgs.qemu}/bin/qemu-img", "convert", "-f", "qcow2", "-O", "raw", str(disk), str(raw)], check=True)
        checked = subprocess.run(["${pkgs.e2fsprogs}/bin/e2fsck", "-fy", str(raw)])
        assert checked.returncode in (0, 1)
        subprocess.run(["${pkgs.e2fsprogs}/bin/debugfs", "-w", "-R", "ln /.host-persistence-ready.saved /.host-persistence-ready", str(raw)], check=True)
        subprocess.run(["${pkgs.e2fsprogs}/bin/debugfs", "-w", "-R", "unlink /.host-persistence-ready.saved", str(raw)], check=True)
        subprocess.run(["${pkgs.qemu}/bin/qemu-img", "convert", "-f", "raw", "-O", "qcow2", str(raw), str(repaired)], check=True)
        os.replace(repaired, disk)
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("getent shadow repparw | cut -d: -f2 > /run/actual-password; cmp -s /persist/expected-password /run/actual-password")
        machine.succeed("test -s /run/secrets-for-users/bootstrap; test -e /var/lib/auto-update/PAUSE")
  '';
}
