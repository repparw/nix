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
  sameFs =
    (hosts.pi.extendModules {
      modules = [
        { fileSystems."/".device = lib.mkForce pi.fileSystems."/persist".device; }
      ];
    }).config;
  assertCommonPersistence =
    host: config: mounts:
    let
      require = condition: message: lib.assertMsg condition "${host}: ${message}";
      persistence = config.environment.persistence."/persist";
      root = config.fileSystems."/";
      backup = config.services.restic.backups.offsite;
    in
    assert require (config.modules.persistence.enable) "host persistence must be enabled";
    assert require (config.modules.persistence.mutableAccounts) "mutable accounts must be enabled";
    assert require persistence.enable "/persist persistence must be enabled";
    assert require (config.fileSystems."/persist".neededForBoot) "/persist must be available at boot";
    assert require (root.device == "tmpfs") "the root device must be tmpfs";
    assert require (root.fsType == "tmpfs") "the root filesystem must be tmpfs";
    assert require (root.neededForBoot) "root must be available at boot";
    assert require (lib.elem "x-initrd.mount" root.options) "root must mount in the initrd";
    assert require (lib.elem "mode=0755" root.options) "root must use mode 0755";
    assert require (lib.elem "size=50%" root.options) "root tmpfs must have a 50% size limit";
    assert require (
      config.sops.age.sshKeyPaths == [ "/persist/etc/ssh/ssh_host_ed25519_key" ]
    ) "SOPS must read the SSH host key from /persist";
    assert require (lib.any (
      mount: mount.where == "/etc" && mount.what == "/persist/etc"
    ) mounts) "/etc must mount from /persist/etc";
    assert require
      (lib.elem "sysroot-etc.mount" config.boot.initrd.systemd.services.initrd-nixos-activation.requires)
      "initrd activation must require sysroot-etc.mount";
    assert require
      (lib.elem "initrd-nixos-activation.service" config.boot.initrd.systemd.services.check-persistence-state.requiredBy)
      "initrd activation must require the persistence state check";
    assert require (lib.any (
      mount: mount.where == "/sysroot/var/lib/nixos" && mount.what == "/sysroot/persist/var/lib/nixos"
    ) config.boot.initrd.systemd.mounts) "/var/lib/nixos must mount from /persist in the initrd";
    assert require (lib.any (
      entry: entry.file == "/var/lib/systemd/random-seed" && entry.method == "symlink"
    ) persistence.files) "the random seed must persist as a symlink";
    assert require (lib.any (
      entry: entry.directory or null == "/var/lib/tailscale"
    ) persistence.directories) "Tailscale state must persist";
    assert require (config.users.mutableUsers) "users must be mutable";
    assert require (lib.any (
      mount: mount.where == "/var/lib/host-recovery"
    ) mounts) "/var/lib/host-recovery must have a persistence mount";
    assert require (lib.all (path: lib.elem path backup.paths) [
      "/etc"
      "/boot"
      "/root"
      "/home/repparw"
      "/var/lib/nixos"
      "/var/lib/nixos-containers"
      "/var/lib/systemd/timers"
      "/var/lib/host-recovery"
      "/home/containers/config"
      "/var/lib/traefik"
    ]) "offsite backup must include the shared paths";
    assert require (lib.elem "/home/repparw/.swapfile" backup.exclude)
      "offsite backup must exclude the swapfile";
    assert require (lib.elem "/var/lib/nixos-containers/*/nix" backup.exclude)
      "offsite backup must exclude container Nix stores";
    assert require (lib.all (
      assertion: assertion.assertion
    ) config.assertions) "NixOS configuration assertions must pass";
    assert require (lib.elem "--one-file-system" backup.extraBackupArgs)
      "offsite backup must use --one-file-system";
    true;
  piResult =
    assert assertCommonPersistence "pi" pi piMounts;
    assert pi.fileSystems."/home/repparw".neededForBoot;
    assert !(lib.elem "nofail" pi.fileSystems."/home/repparw".options);
    assert !(lib.any (mount: mount.where == "/home/repparw") piMounts);
    assert lib.any (entry: entry.directory or null == "/var/lib/host-recovery") (
      pi.environment.persistence."/persist".directories
    );
    {
      disabledByDefault = false;
      tmpfsRoot = true;
      persistentMounts = map (mount: mount.where) piMounts;
      earlySopsKey = builtins.head pi.sops.age.sshKeyPaths;
    };
  epsilonResult =
    assert assertCommonPersistence "epsilon" epsilon epsilonMounts;
    assert
      epsilon.fileSystems."/persist".device
      == "/dev/disk/by-partuuid/daa9a574-99f0-449e-b43a-463650870efb";
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
    assert epsilon.boot.loader.grub.copyKernels;
    assert (lib.head epsilon.boot.loader.grub.mirroredBoots).path == "/persist/boot";
    assert epsilon.fileSystems."/boot".device == "/persist/boot";
    assert lib.elem "bind" epsilon.fileSystems."/boot".options;
    assert !epsilon.fileSystems."/boot".neededForBoot;
    assert lib.any (mount: mount.where == "/home/repparw") epsilonMounts;
    assert lib.any (mount: mount.where == "/var/log") epsilonMounts;
    assert lib.elem "sysroot-nix.mount"
      epsilon.boot.initrd.systemd.services.initrd-nixos-activation.requires;
    assert lib.elem "sysroot-var-lib-nixos.mount"
      epsilon.boot.initrd.systemd.services.initrd-nixos-activation.requires;
    assert lib.any (entry: entry.directory or null == "/var/log") (
      epsilon.environment.persistence."/persist".directories
    );
    assert lib.any (mount: mount.where == "/var/lib/credential-remediation") epsilonMounts;
    {
      disabledByDefault = false;
      tmpfsRoot = true;
      persistentMounts = map (mount: mount.where) epsilonMounts;
      earlySopsKey = builtins.head epsilon.sops.age.sshKeyPaths;
    };
in
assert !(hosts.alpha.config.modules ? persistence);
assert !(hosts.alpha.options.modules.backup ? hostRecovery);
assert hosts.alpha.config.services.restic.backups.offsite.extraBackupArgs == [ ];
assert lib.all (
  host:
  !(lib.any (p: (p.meta.mainProgram or "") == "host-recovery") host.config.environment.systemPackages)
) (lib.attrValues hosts);
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
assert sameFs.environment.persistence."/persist".files == [ ];
pkgs.writeText "host-persistence-evaluation.json" (
  builtins.toJSON {
    pi = piResult;
    epsilon = epsilonResult;
  }
)
