{
  inputs,
  lib,
  pkgs,
}:
let
  require =
    host: condition: message:
    lib.assertMsg condition "${host}: ${message}";
  hosts = inputs.self.nixosConfigurations;
  mkHost =
    host:
    let
      config = hosts.${host}.config;
    in
    {
      inherit host config;
      mounts = lib.filter (mount: lib.hasPrefix "/persist/" mount.what) config.systemd.mounts;
    };
  piHost = mkHost "pi";
  epsilonHost = mkHost "epsilon";
  pi = piHost.config;
  epsilon = epsilonHost.config;
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
    {
      host,
      config,
      mounts,
    }:
    let
      persistence = config.environment.persistence."/persist";
      root = config.fileSystems."/";
    in
    assert require host (config.modules.persistence.enable) "host persistence must be enabled";
    assert require host (config.modules.persistence.mutableAccounts) "mutable accounts must be enabled";
    assert require host persistence.enable "/persist persistence must be enabled";
    assert require host (config.fileSystems."/persist".neededForBoot
    ) "/persist must be available at boot";
    assert require host (root.device == "tmpfs") "the root device must be tmpfs";
    assert require host (root.fsType == "tmpfs") "the root filesystem must be tmpfs";
    assert require host (root.neededForBoot) "root must be available at boot";
    assert require host (lib.elem "x-initrd.mount" root.options) "root must mount in the initrd";
    assert require host (lib.elem "mode=0755" root.options) "root must use mode 0755";
    assert require host (lib.elem "size=50%" root.options) "root tmpfs must have a 50% size limit";
    assert require host (
      config.sops.age.sshKeyPaths == [ "/persist/etc/ssh/ssh_host_ed25519_key" ]
    ) "SOPS must read the SSH host key from /persist";
    assert require host (lib.any (
      mount: mount.where == "/etc" && mount.what == "/persist/etc"
    ) mounts) "/etc must mount from /persist/etc";
    assert require host
      (lib.elem "sysroot-etc.mount" config.boot.initrd.systemd.services.initrd-nixos-activation.requires)
      "initrd activation must require sysroot-etc.mount";
    assert require host
      (lib.elem "initrd-nixos-activation.service" config.boot.initrd.systemd.services.check-persistence-state.requiredBy)
      "initrd activation must require the persistence state check";
    assert require host (lib.any (
      mount: mount.where == "/sysroot/var/lib/nixos" && mount.what == "/sysroot/persist/var/lib/nixos"
    ) config.boot.initrd.systemd.mounts) "/var/lib/nixos must mount from /persist in the initrd";
    assert require host (lib.any (
      entry: entry.file == "/var/lib/systemd/random-seed" && entry.method == "symlink"
    ) persistence.files) "the random seed must persist as a symlink";
    assert require host (config.users.mutableUsers) "users must be mutable";
    true;
  assertServicePersistence =
    {
      host,
      config,
      mounts,
    }:
    let
      persistence = config.environment.persistence."/persist";
    in
    assert require host (lib.any (
      entry: entry.directory or null == "/var/lib/tailscale"
    ) persistence.directories) "Tailscale state must persist";
    assert require host (lib.any (
      entry: entry.directory or null == "/var/lib/host-recovery"
    ) persistence.directories) "host-recovery state must be declared persistent";
    assert require host (lib.any (
      mount: mount.where == "/var/lib/host-recovery"
    ) mounts) "/var/lib/host-recovery must have a persistence mount";
    true;
  assertOffsiteBackup =
    host: backup:
    let
      missingPaths = lib.subtractLists backup.paths [
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
      ];
    in
    assert require host (
      missingPaths == [ ]
    ) "offsite backup is missing paths: ${lib.concatStringsSep ", " missingPaths}";
    assert require host (lib.elem "/home/repparw/.swapfile" backup.exclude)
      "offsite backup must exclude the swapfile";
    assert require host (lib.elem "/var/lib/nixos-containers/*/nix" backup.exclude)
      "offsite backup must exclude container Nix stores";
    true;
  mkPersistenceResult =
    {
      host,
      config,
      mounts,
    }:
    let
      failures = lib.filter (assertion: !assertion.assertion) config.assertions;
    in
    assert require host (failures == [ ]) (
      lib.concatMapStringsSep "\n" (assertion: assertion.message) failures
    );
    {
      disabledByDefault = false;
      tmpfsRoot = true;
      persistentMounts = map (mount: mount.where) mounts;
      earlySopsKey = builtins.head config.sops.age.sshKeyPaths;
    };
  piResult =
    assert assertCommonPersistence piHost;
    assert assertServicePersistence piHost;
    assert assertOffsiteBackup "pi" pi.services.restic.backups.offsite;
    assert require "pi" (pi.fileSystems."/home/repparw".neededForBoot
    ) "/home/repparw must be available at boot";
    assert require "pi" (
      !(lib.elem "nofail" pi.fileSystems."/home/repparw".options)
    ) "/home/repparw must mount without nofail";
    assert require "pi" (
      !(lib.any (mount: mount.where == "/home/repparw") piHost.mounts)
    ) "/home/repparw must use its own filesystem";
    mkPersistenceResult piHost;
  epsilonResult =
    assert assertCommonPersistence epsilonHost;
    assert assertServicePersistence epsilonHost;
    assert assertOffsiteBackup "epsilon" epsilon.services.restic.backups.offsite;
    assert require "epsilon" (
      epsilon.fileSystems."/persist".device
      == "/dev/disk/by-partuuid/daa9a574-99f0-449e-b43a-463650870efb"
    ) "/persist must use its assigned partition";
    # The initrd owns the /nix bind. GRUB must resolve the backing
    # filesystem, or its runtime mount detection emits /store/... paths.
    assert require "epsilon" (
      !(epsilon.fileSystems ? "/nix")
    ) "the initrd must own the /nix bind mount";
    assert require "epsilon" (lib.any
      (
        mount:
        mount.where == "/sysroot/nix"
        && mount.what == "/sysroot/persist/nix"
        && mount.options == "bind"
        && lib.elem "sysroot-persist.mount" mount.requires
        && lib.elem "initrd-fs.target" mount.wantedBy
      )
      epsilon.boot.initrd.systemd.mounts
    ) "the initrd must bind /nix from /persist for initrd-fs.target";
    assert require "epsilon" (epsilon.boot.loader.grub.copyKernels) "GRUB must copy kernels";
    assert require "epsilon" (
      (lib.head epsilon.boot.loader.grub.mirroredBoots).path == "/persist/boot"
    ) "GRUB must mirror its boot files to /persist/boot";
    assert require "epsilon" (
      epsilon.fileSystems."/boot".device == "/persist/boot"
    ) "/boot must mount from /persist/boot";
    assert require "epsilon" (lib.elem "bind"
      epsilon.fileSystems."/boot".options
    ) "/boot must use a bind mount";
    assert require "epsilon" (
      !epsilon.fileSystems."/boot".neededForBoot
    ) "/boot must mount after the initrd";
    assert require "epsilon" (lib.any (
      mount: mount.where == "/home/repparw"
    ) epsilonHost.mounts) "/home/repparw must have a persistence mount";
    assert require "epsilon" (lib.any (
      mount: mount.where == "/var/log"
    ) epsilonHost.mounts) "/var/log must have a persistence mount";
    assert require "epsilon"
      (lib.elem "sysroot-nix.mount" epsilon.boot.initrd.systemd.services.initrd-nixos-activation.requires)
      "initrd activation must require sysroot-nix.mount";
    assert require "epsilon"
      (lib.elem "sysroot-var-lib-nixos.mount" epsilon.boot.initrd.systemd.services.initrd-nixos-activation.requires)
      "initrd activation must require sysroot-var-lib-nixos.mount";
    assert require "epsilon" (lib.any (entry: entry.directory or null == "/var/log") (
      epsilon.environment.persistence."/persist".directories
    )) "/var/log must be declared persistent";
    assert require "epsilon" (lib.any (
      mount: mount.where == "/var/lib/credential-remediation"
    ) epsilonHost.mounts) "credential remediation must have a persistence mount";
    mkPersistenceResult epsilonHost;
in
assert require "alpha" (!(hosts.alpha.config.modules ? persistence)) "persistence must be absent";
assert require "alpha" (
  !(hosts.alpha.options.modules.backup ? hostRecovery)
) "host recovery must be absent";
assert require "alpha" (
  hosts.alpha.config.services.restic.backups.offsite.extraBackupArgs == [ ]
) "offsite backup must have no extra arguments";
assert require "pi"
  (lib.elem "--one-file-system" pi.services.restic.backups.offsite.extraBackupArgs)
  "offsite backup must use --one-file-system";
assert require "epsilon"
  (lib.elem "--one-file-system" epsilon.services.restic.backups.offsite.extraBackupArgs)
  "offsite backup must use --one-file-system";
assert lib.all (
  host:
  require host (
    !(lib.any (
      p: (p.meta.mainProgram or "") == "host-recovery"
    ) hosts.${host}.config.environment.systemPackages)
  ) "host-recovery must be absent from system packages"
) (lib.attrNames hosts);
assert require "pi" (lib.elem "/boot/firmware" pi.services.restic.backups.offsite.paths)
  "offsite backup must include /boot/firmware";
assert require "epsilon" (lib.elem "/boot/efi" epsilon.services.restic.backups.offsite.paths)
  "offsite backup must include /boot/efi";
assert require "epsilon" (
  epsilon.modules.services.definitions.paperless.backup.path == "/home/containers/config/paper/export"
) "Paperless backups must use /home/containers/config/paper/export";
assert require "epsilon without boot-ready persistence" (lib.any (
  assertion: !assertion.assertion && lib.hasPrefix "Host persistence requires" assertion.message
) unprepared.assertions) "expected an assertion about persistence boot readiness";
assert require "epsilon without mutable accounts" (lib.any (
  assertion: !assertion.assertion && lib.hasPrefix "Mutable passwords require" assertion.message
) unprepared.assertions) "expected an assertion about mutable passwords";
assert require "pi with root and persistence on the same filesystem" (
  sameFs.environment.persistence."/persist".files == [ ]
) "persistence must declare no file entries";
pkgs.writeText "host-persistence-evaluation.json" (
  builtins.toJSON {
    pi = piResult;
    epsilon = epsilonResult;
  }
)
