{ ... }:
{
  den.aspects.pi-generation-retention.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      retention = pkgs.writeShellApplication {
        name = "pi-generation-retention";
        runtimeInputs = [
          config.nix.package
          pkgs.python3
        ];
        text = ''
          exec python3 ${../scripts/pi-generation-retention.py} "$@"
        '';
      };
    in
    {
      environment.systemPackages = [ retention ];
      nix.gc.dates = lib.mkForce "daily";
      nix.gc.options = lib.mkForce "";
      systemd.services.nix-gc.script = lib.mkForce ''
        # Three generations: current, booted, and one rollback. The 40G nvme
        # cannot hold five closures plus the working set for a deploy
        # (observed 2026-11-10 to 11-11: builds ENOSPC or the min-free
        # auto-GC deletes in-flight substitutes mid-build).
        exec ${lib.getExe retention} apply --keep 3
      '';
    };
}
