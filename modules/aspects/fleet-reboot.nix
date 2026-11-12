{ den, ... }:
{
  den.aspects.fleet-reboot.nixos =
    { lib, pkgs, ... }:
    let
      predicate = pkgs.writeShellApplication {
        name = "fleet-reboot-required";
        runtimeInputs = [ pkgs.coreutils ];
        text = builtins.readFile ../scripts/fleet-reboot-required.sh;
      };
    in
    {
      options.modules.fleet-reboot.predicate = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "Exit-code predicate for a staged kernel/initrd that differs from the running boot";
      };
      config = {
        modules.fleet-reboot.predicate = predicate;
        environment.systemPackages = [ predicate ];
      };
    };
}
