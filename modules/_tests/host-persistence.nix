{
  inputs,
  lib,
  pkgs,
}:
let
  hosts = inputs.self.nixosConfigurations;
  persistenceMounts =
    config: lib.filter (mount: lib.hasPrefix "/persist/" mount.what) config.systemd.mounts;
  prepared =
    host:
    (hosts.${host}.extendModules {
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
    (hosts.pi.extendModules {
      modules = [
        { modules.persistence.enable = true; }
        # Keep the "unprepared backing volume" spirit now that pi carries a
        # prepared /persist: force its boot flag off for this probe.
        { fileSystems."/persist".neededForBoot = lib.mkForce false; }
      ];
    }).config;
  verifyHost =
    host:
    let
      normal = hosts.${host}.config;
      enabled = prepared host;
      mounts = persistenceMounts enabled;
    in
    assert !normal.modules.persistence.enable;
    assert !normal.modules.persistence.mutableAccounts;
    assert !normal.environment.persistence."/persist".enable;
    assert persistenceMounts normal == [ ];
    assert (normal.fileSystems ? "/persist") == (host == "pi");
    assert normal.sops.age.sshKeyPaths == [ "/etc/ssh/ssh_host_ed25519_key" ];
    assert enabled.fileSystems."/".fsType == normal.fileSystems."/".fsType;
    assert enabled.sops.age.sshKeyPaths == [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    assert lib.any (mount: mount.where == "/etc" && mount.what == "/persist/etc") mounts;
    assert lib.elem "sysroot-etc.mount"
      enabled.boot.initrd.systemd.services.initrd-nixos-activation.requires;
    assert lib.elem "initrd-nixos-activation.service"
      enabled.boot.initrd.systemd.services.check-persistence-state.requiredBy;
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
    assert lib.any (
      mount: mount.where == "/sysroot/var/lib/nixos" && mount.what == "/sysroot/persist/var/lib/nixos"
    ) enabled.boot.initrd.systemd.mounts;
    assert lib.all (assertion: assertion.assertion) enabled.assertions;
    {
      disabledByDefault = true;
      persistentMounts = map (mount: mount.where) mounts;
      earlySopsKey = builtins.head enabled.sops.age.sshKeyPaths;
    };
  results = lib.genAttrs [ "pi" "epsilon" ] verifyHost;
in
assert !(hosts.alpha.config.modules ? persistence);
assert !hosts.alpha.config.modules.backup.hostRecovery.enable;
assert lib.elem "/boot/firmware" hosts.pi.config.services.restic.backups.offsite.paths;
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
assert (prepared "pi").fileSystems."/home/repparw".neededForBoot;
assert !(lib.elem "nofail" (prepared "pi").fileSystems."/home/repparw".options);
assert lib.elem "nofail" hosts.pi.config.fileSystems."/home/repparw".options;
assert !(lib.any (mount: mount.where == "/home/repparw") (persistenceMounts (prepared "pi")));
assert lib.any (mount: mount.where == "/home/repparw") (persistenceMounts (prepared "epsilon"));
pkgs.writeText "host-persistence-evaluation.json" (builtins.toJSON results)
