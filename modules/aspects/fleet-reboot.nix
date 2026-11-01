{ den, ... }:
{
  den.aspects.fleet-reboot.nixos =
    { lib, pkgs, ... }:
    let
      # One predicate for every consumer: the health collector exports it as
      # fleet_reboot_required, the headless reboot sequence gates on it, and
      # fleet debug prints it. Every host carries it so the sequence can
      # evaluate a remote host over plain ssh without a heredoc copy.
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
