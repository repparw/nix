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
        exec ${lib.getExe retention} apply --keep 5
      '';
    };
}
