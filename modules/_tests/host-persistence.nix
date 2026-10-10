{
  inputs,
  lib,
  pkgs,
}:
let
  hosts = inputs.self.nixosConfigurations;
  persistenceMounts =
    config: lib.filter (mount: lib.hasPrefix "/persist/" mount.what) config.systemd.mounts;
  pi = hosts.pi.config;
  epsilon = hosts.epsilon.config;
  piMounts = persistenceMounts pi;
  epsilonMounts = persistenceMounts epsilon;
  # The unprepared probe proves the refusal paths on a persistence-disabled
  # base: pi and epsilon now carry prepared /persist volumes and enabled
  # persistence in their base configurations, so the boot flag is forced off
  # to reproduce the "unprepared backing volume" state.
  unprepared =
    (hosts.epsilon.extendModules {
      modules = [
        {
          modules.persistence.enable = true;
          modules.persistence.mutableAccounts = lib.mkForce false;
        }
        { fileSystems."/persist".neededForBoot = lib.mkForce false; }
      ];
    }).config;
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
    assert lib.any (mount: mount.where == "/var/lib/host-recovery") piMounts;
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
    assert epsilon.modules.persistence.enable;
    assert epsilon.modules.persistence.mutableAccounts;
    assert epsilon.environment.persistence."/persist".enable;
    assert
      epsilon.fileSystems."/persist".device
      == "/dev/disk/by-partuuid/daa9a574-99f0-449e-b43a-463650870efb";
    assert epsilon.fileSystems."/persist".neededForBoot;
    assert epsilon.fileSystems."/".device == "tmpfs";
    assert epsilon.fileSystems."/".fsType == "tmpfs";
    assert epsilon.fileSystems."/".neededForBoot;
    assert lib.elem "x-initrd.mount" epsilon.fileSystems."/".options;
    assert lib.elem "mode=0755" epsilon.fileSystems."/".options;
    assert lib.elem "size=50%" epsilon.fileSystems."/".options;
    # The initrd owns the /nix bind. GRUB must resolve the backing
    # filesystem, or its runtime mount detection emits /store/... paths.
    assert !(epsilon.fileSystems ? "/nix");
    assert lib.any (
      mount:
      mount.where == "/sysroot/nix"
      && mount.what == "/sysroot/persist/nix"
      && mount.options == "bind"
      && lib.elem "sysroot-persist.mount" mount.requires
      && lib.elem "initrd-fs.target" mount.wantedBy
    ) epsilon.boot.initrd.systemd.mounts;
    assert epsilon.boot.loader.grub.storePath == "/persist/nix/store";
    assert epsilon.fileSystems."/boot".device == "/persist/boot";
    assert lib.elem "bind" epsilon.fileSystems."/boot".options;
    assert !epsilon.fileSystems."/boot".neededForBoot;
    assert epsilon.sops.age.sshKeyPaths == [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    assert lib.any (mount: mount.where == "/etc" && mount.what == "/persist/etc") epsilonMounts;
    assert lib.any (mount: mount.where == "/home/repparw") epsilonMounts;
    assert lib.any (mount: mount.where == "/var/log") epsilonMounts;
    assert lib.any (mount: mount.where == "/var/lib/ddclient") epsilonMounts;
    assert lib.elem "sysroot-nix.mount"
      epsilon.boot.initrd.systemd.services.initrd-nixos-activation.requires;
    assert lib.elem "sysroot-var-lib-nixos.mount"
      epsilon.boot.initrd.systemd.services.initrd-nixos-activation.requires;
    assert lib.elem "sysroot-etc.mount"
      epsilon.boot.initrd.systemd.services.initrd-nixos-activation.requires;
    assert lib.elem "initrd-nixos-activation.service"
      epsilon.boot.initrd.systemd.services.check-persistence-state.requiredBy;
    assert lib.any (
      mount: mount.where == "/sysroot/var/lib/nixos" && mount.what == "/sysroot/persist/var/lib/nixos"
    ) epsilon.boot.initrd.systemd.mounts;
    assert lib.any (entry: entry.directory or null == "/var/log") (
      epsilon.environment.persistence."/persist".directories
    );
    assert lib.any (entry: entry.directory or null == "/var/lib/ddclient") (
      epsilon.environment.persistence."/persist".directories
    );
    # Same same-fs landmine as pi: the random-seed symlink must stay absent
    # during the migration; see modules/hosts/epsilon.nix.
    assert epsilon.environment.persistence."/persist".files == [ ];
    assert epsilon.users.mutableUsers;
    assert epsilon.modules.backup.hostRecovery.enable;
    assert lib.any (mount: mount.where == "/var/lib/host-recovery") epsilonMounts;
    assert lib.any (mount: mount.where == "/var/lib/credential-remediation") epsilonMounts;
    assert lib.all (path: lib.elem path epsilon.services.restic.backups.offsite.paths) [
      "/etc"
      "/boot"
      "/root"
      "/home/repparw"
      "/var/lib/nixos"
      "/var/lib/nixos-containers"
    ];
    assert lib.elem "/home/repparw/.swapfile" epsilon.services.restic.backups.offsite.exclude;
    assert lib.elem "/var/lib/nixos-containers/*/nix" epsilon.services.restic.backups.offsite.exclude;
    assert lib.all (assertion: assertion.assertion) epsilon.assertions;
    {
      disabledByDefault = false;
      tmpfsRoot = true;
      persistentMounts = map (mount: mount.where) epsilonMounts;
      earlySopsKey = builtins.head epsilon.sops.age.sshKeyPaths;
    };
in
assert !(hosts.alpha.config.modules ? persistence);
assert !hosts.alpha.config.modules.backup.hostRecovery.enable;
assert lib.elem "/boot/firmware" pi.services.restic.backups.offsite.paths;
assert lib.elem "/boot/efi" epsilon.services.restic.backups.offsite.paths;
assert
  epsilon.modules.services.definitions.paperless.backup.path
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
