{
  inputs,
  pkgs,
}:
let
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
  recovery = pkgs.writeShellApplication {
    name = "host-recovery";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      util-linux
      systemd
      restic
      rclone
      jq
      sops
      ssh-to-age
      sqlite
      gnutar
    ];
    text = ''
      export RECOVERY_PATHS_FILE=${pkgs.writeText "test-backup-paths" "/etc\n/home/repparw\n/var/lib/nixos\n/var/lib/test-service\n/var/lib/auto-update\n/var/lib/host-recovery\n"}
      export RECOVERY_EXCLUDES_FILE=${pkgs.writeText "test-backup-excludes" ""}
      export RECOVERY_UNITS_FILE=${pkgs.writeText "test-backup-units" "recovery-test-writer.service\n"}
      export RECOVERY_CAPTURE_PATHS_FILE=${pkgs.writeText "test-capture-paths" "/home/repparw/services/hass\n"}
      export RECOVERY_BOOTSTRAP_FILE=${fixture}/secret.yaml
      ${builtins.readFile ../scripts/host-recovery.sh}
    '';
  };
  common = { config, ... }: {
    imports = [
      persistence
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
    systemd.services.recovery-test-writer = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
      };
    };
    environment.systemPackages = [
      recovery
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
    import re
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
        machine.succeed(restic + "init")
        machine.succeed("mkdir -p /home/repparw/services/hass; cp /var/lib/test-service/data.db /home/repparw/services/hass/home-assistant_v2.db")
        helper = "RESTIC_REPOSITORY=/persist/test-repository RESTIC_PASSWORD_FILE=/run/restic-password host-recovery "
        machine.succeed(helper + "full --quiesce > /run/backup-result")
        machine.succeed("systemctl is-active --quiet recovery-test-writer.service; test -s /var/lib/host-recovery/application-state.tar")
        snapshot = machine.succeed(restic + "snapshots --latest 1 --json | ${pkgs.jq}/bin/jq -r '.[0].id'").strip()
        result = machine.succeed(helper + "restore-check " + snapshot)
        assert "Restored HA database integrity_check passed." in result
        restored_match = re.search(r"Restored files retained at (\S+)", result)
        assert restored_match is not None
        restored = restored_match.group(1)
        machine.succeed("ln -s " + restored + " /restored")
        machine.succeed("cmp -s /etc/shadow /restored/etc/shadow; cmp -s /etc/ssh/ssh_host_ed25519_key /restored/etc/ssh/ssh_host_ed25519_key")
        machine.succeed("test $(stat -c %a /restored/etc/shadow) = $(stat -c %a /etc/shadow)")
        machine.succeed("test $(stat -c %u:%g /restored/home/repparw/state) = $(stat -c %u:%g /home/repparw/state)")
        machine.succeed("getfattr --only-values -n user.recovery /restored/home/repparw/state | grep -qx preserved")
        machine.succeed("getfacl -cp /home/repparw/state > /run/acl-before; getfacl -cp /restored/home/repparw/state > /run/acl-after; cmp -s /run/acl-before /run/acl-after")
        assert machine.succeed("sqlite3 /restored/var/lib/test-service/data.db 'pragma integrity_check; select value from state;'").strip() == "ok\n42"

    with subtest("Abrupt restart retains completed password and state writes"):
        machine.succeed("sync")
        machine.crash()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("getent shadow repparw | cut -d: -f2 > /run/actual-password; cmp -s /persist/expected-password /run/actual-password")
        machine.succeed("test -e /var/lib/auto-update/PAUSE; test -s /run/secrets-for-users/bootstrap")

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
