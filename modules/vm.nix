{ den, inputs, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      packages = den.lib.nh.denPackages { fromFlake = true; } pkgs // {
        vmAlpha = pkgs.writeShellApplication {
          name = "vm-alpha";
          text =
            let
              host = inputs.self.nixosConfigurations.alpha.config;
            in
            ''
              ${host.system.build.vm}/bin/run-${host.networking.hostName}-vm "$@"
            '';
        };

        # vmBeta stays parked until beta hardware is back.
      };

      apps = {
        vmAlpha = {
          type = "app";
          program = "${config.packages.vmAlpha}/bin/vm-alpha";
          meta.description = "Run the alpha NixOS VM";
        };

        # vmBeta stays parked until beta hardware is back.
      };
    };
}
