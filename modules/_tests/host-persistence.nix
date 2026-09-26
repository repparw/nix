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
          fileSystems."/persist" = {
            device = "/dev/disk/by-label/persistence-test";
            fsType = "ext4";
            neededForBoot = true;
          };
        }
      ];
    }).config;
  unprepared =
    (hosts.pi.extendModules {
      modules = [ { modules.persistence.enable = true; } ];
    }).config;
  verifyHost =
    host:
    let
      normal = hosts.${host}.config;
      enabled = prepared host;
      mounts = persistenceMounts enabled;
    in
    assert !normal.modules.persistence.enable;
    assert !normal.environment.persistence."/persist".enable;
    assert persistenceMounts normal == [ ];
    assert !(normal.fileSystems ? "/persist");
    assert normal.sops.age.sshKeyPaths == [ "/etc/ssh/ssh_host_ed25519_key" ];
    assert enabled.fileSystems."/".fsType == normal.fileSystems."/".fsType;
    assert enabled.sops.age.sshKeyPaths == [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    assert lib.any (mount: mount.where == "/etc/ssh" && mount.what == "/persist/etc/ssh") mounts;
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
assert lib.any (
  assertion: !assertion.assertion && lib.hasPrefix "Host persistence requires" assertion.message
) unprepared.assertions;
assert (prepared "pi").fileSystems."/home/repparw".neededForBoot;
assert !(lib.elem "nofail" (prepared "pi").fileSystems."/home/repparw".options);
assert lib.elem "nofail" hosts.pi.config.fileSystems."/home/repparw".options;
assert !(lib.any (mount: mount.where == "/home/repparw") (persistenceMounts (prepared "pi")));
assert lib.any (mount: mount.where == "/home/repparw") (persistenceMounts (prepared "epsilon"));
pkgs.writeText "host-persistence-evaluation.json" (builtins.toJSON results)
