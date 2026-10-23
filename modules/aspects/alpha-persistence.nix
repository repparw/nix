{ den, ... }:
{
  den.aspects.alpha-persistence = {
    includes = [ den.aspects.persistence ];

    nixos =
      { config, lib, ... }:
      {
        assertions = [
          {
            assertion = !config.modules.persistence.enable || config.fileSystems."/".fsType == "tmpfs";
            message = "Alpha persistence requires a separately verified tmpfs-root layout; see docs/runbooks/alpha-impermanence.md.";
          }
        ];

        environment.persistence."/persist".directories = [
          "/home"
          "/var/log"
          "/var/lib"
        ];

        # The initial backing layout reuses the live @ subvolume. A seed
        # symlink installed before the tmpfs boot would point back at itself.
        environment.persistence."/persist".files = lib.mkForce [ ];
      };
  };
}
