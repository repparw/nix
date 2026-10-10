{
  inputs,
  lib,
  pkgs,
}:
let
  hosts = inputs.self.nixosConfigurations;
  persistenceMounts =
    config: lib.filter (mount: lib.hasPrefix "/persist/" mount.what) config.systemd.mounts;
  # Epsilon keeps the aspect probes on a persistence-disabled base: the
  # overlay proves the generated wiring, the unprepared probe proves the
  # refusal paths. Pi's base configuration is itself the enabled state and is
  # verified directly below.
  prepared =
    (hosts.epsilon.extendModules {
      modules = [
        {
          modules.persistence.enable = true;
          modules.persistence.mutableAccounts = true;
          fileSystems."/persist" = {
            device = lib.mkForce "/dev/disk/by-label/persistence-test";
            fsType = lib.mkForce "ext4";
            neededForBoot = lib.mkForce true;
          };
        }
      ];
    }).config;
  unprepared =
    (hosts.epsilon.extendModules {
      modules = [ { modules.persistence.enable = true; } ];
    }).config;
  pi = hosts.pi.config;
  piMounts = persistenceMounts pi;
  piResult =
    assert pi.modules.persistence.enable;
    assert pi.modules.persistence.mutableAccounts;
    assert pi.environment.persistence."/persist".enable;
    assert pi.fileSystems."/persist".neededForBoot;
    assert pi.fileSystems."/".device == "tmpfs";
    assert pi.fileSystems."/".fsType == "tmpfs";
    assert pi.fileSystems."/".neededForBoot;
    assert lib.elem "x-initrd.mount" pi.fileSystems."/".options;
    assert lib.elem "mode=0755" pi.fileSystems."/".options;
    assert lib.elem "size=50%" pi.fileSystems."/".options;
    assert pi.sops.age.sshKeyPaths == [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    assert lib.any (mount: mount.where == "/etc" && mount.what == "/persist/etc") piMounts;
    assert lib.elem "sysroot-etc.mount"
      pi.boot.initrd.systemd.services.initrd-nixos-activation.requires;
    assert lib.elem "initrd-nixos-activation.service"
      pi.boot.initrd.systemd.services.check-persistence-state.requiredBy;
    assert lib.any (
      mount: mount.where == "/sysroot/var/lib/nixos" && mount.what == "/sysroot/persist/var/lib/nixos"
    ) pi.boot.initrd.systemd.mounts;
    assert pi.fileSystems."/home/repparw".neededForBoot;
    assert !(lib.elem "nofail" pi.fileSystems."/home/repparw".options);
    assert !(lib.any (mount: mount.where == "/home/repparw") piMounts);
    assert lib.any (entry: entry.directory or null == "/var/lib/host-recovery") (
      pi.environment.persistence."/persist".directories
    );
    # The random-seed symlink entry is deliberately absent on pi: with / and
    # /persist on one filesystem it would be self-referential (ELOOP) and
    # break every live switch; see modules/hosts/pi.nix.
    assert pi.environment.persistence."/persist".files == [ ];
    assert pi.users.mutableUsers;
    assert pi.modules.backup.hostRecovery.enable;
    assert lib.all (path: lib.elem path pi.services.restic.backups.offsite.paths) [
      "/etc"
      "/boot"
      "/root"
      "/home/repparw"
      "/var/lib/nixos"
      "/var/lib/nixos-containers"
    ];
    assert lib.elem "/home/repparw/.swapfile" pi.services.restic.backups.offsite.exclude;
    assert lib.elem "/var/lib/nixos-containers/*/nix" pi.services.restic.backups.offsite.exclude;
    assert lib.all (assertion: assertion.assertion) pi.assertions;
    {
      disabledByDefault = false;
      tmpfsRoot = true;
      persistentMounts = map (mount: mount.where) piMounts;
      earlySopsKey = builtins.head pi.sops.age.sshKeyPaths;
    };
  epsilonResult =
    let
      normal = hosts.epsilon.config;
      mounts = persistenceMounts prepared;
    in
    assert !normal.modules.persistence.enable;
    assert !normal.modules.persistence.mutableAccounts;
    assert !normal.environment.persistence."/persist".enable;
    assert persistenceMounts normal == [ ];
    assert !(normal.fileSystems ? "/persist");
    assert normal.sops.age.sshKeyPaths == [ "/etc/ssh/ssh_host_ed25519_key" ];
    assert prepared.fileSystems."/".fsType == normal.fileSystems."/".fsType;
    assert prepared.sops.age.sshKeyPaths == [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    assert lib.any (mount: mount.where == "/etc" && mount.what == "/persist/etc") mounts;
    assert lib.elem "sysroot-etc.mount"
      prepared.boot.initrd.systemd.services.initrd-nixos-activation.requires;
    assert lib.elem "initrd-nixos-activation.service"
      prepared.boot.initrd.systemd.services.check-persistence-state.requiredBy;
    assert lib.any (
      mount: mount.where == "/sysroot/var/lib/nixos" && mount.what == "/sysroot/persist/var/lib/nixos"
    ) prepared.boot.initrd.systemd.mounts;
    assert lib.any (mount: mount.where == "/home/repparw") mounts;
    assert normal.users.mutableUsers;
    assert normal.modules.backup.hostRecovery.enable;
    assert lib.all (path: lib.elem path normal.services.restic.backups.offsite.paths) [
      "/etc"
      "/boot"
      "/root"
      "/home/repparw"
      "/var/lib/nixos"
      "/var/lib/nixos-containers"
    ];
    assert lib.elem "/home/repparw/.swapfile" normal.services.restic.backups.offsite.exclude;
    assert lib.elem "/var/lib/nixos-containers/*/nix" normal.services.restic.backups.offsite.exclude;
    assert lib.all (assertion: assertion.assertion) prepared.assertions;
    {
      disabledByDefault = true;
      persistentMounts = map (mount: mount.where) mounts;
      earlySopsKey = builtins.head prepared.sops.age.sshKeyPaths;
    };
in
assert !(hosts.alpha.config.modules ? persistence);
assert !hosts.alpha.config.modules.backup.hostRecovery.enable;
assert lib.elem "/boot/firmware" pi.services.restic.backups.offsite.paths;
assert lib.elem "/boot/efi" hosts.epsilon.config.services.restic.backups.offsite.paths;
assert
  hosts.epsilon.config.modules.services.definitions.paperless.backup.path
  == "/home/containers/config/paper/export";
assert lib.any (
  assertion: !assertion.assertion && lib.hasPrefix "Host persistence requires" assertion.message
) unprepared.assertions;
assert lib.any (
  assertion: !assertion.assertion && lib.hasPrefix "Mutable passwords require" assertion.message
) unprepared.assertions;
pkgs.writeText "host-persistence-evaluation.json" (
  builtins.toJSON {
    pi = piResult;
    epsilon = epsilonResult;
  }
)
