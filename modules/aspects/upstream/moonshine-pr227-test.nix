{
  den,
  lib,
  ...
}:
{
  # Temporary alpha-only Moonshine test build tracking #147 (upstream PR227
  # plus the local reload guard). This replaces the external
  # 91-pr227-test.conf drop-ins and candidate GC root with reviewed config:
  # the generated unit selects the test package directly, deploy-rs owns
  # activation and rollback, and retirement is the moonshine-pr227 cleanup
  # candidate (CI-published once the pinned upstream source carries PR227
  # and the UnitRemoved reload guard). Keep behavior identical to the
  # drop-in it replaces: same package, same environment.
  den.aspects.moonshine-pr227-test.nixos =
    {
      lib,
      pkgs,
      ...
    }:
    {
      nixpkgs.overlays = [
        (final: prev: {
          moonshine-pr227 = final.callPackage ../../_packages/moonshine-pr227 {
            moonshine = prev.moonshine;
          };
        })
      ];

      services.moonshine.package = pkgs.moonshine-pr227;

      # Environment parity with the retired drop-in: the user session bus
      # and runtime dir the test build expects, plus the experiment's
      # stream-pipeline debug logging.
      systemd.services.moonshine.environment = {
        XDG_RUNTIME_DIR = "/run/user/1000";
        DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
        MOONSHINE_LOG = lib.mkForce "moonshine=info,moonshine_core::session::stream::video::pipeline=debug";
      };
    };
}
