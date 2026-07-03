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

        # Disabled while there is no laptop using the beta host config.
        # vmBeta = pkgs.writeShellApplication {
        #   name = "vm-beta";
        #   text =
        #     let
        #       host = inputs.self.nixosConfigurations.beta.config;
        #     in
        #     ''
        #       ${host.system.build.vm}/bin/run-${host.networking.hostName}-vm "$@"
        #     '';
        # };
      };

      apps = {
        vmAlpha = {
          type = "app";
          program = "${config.packages.vmAlpha}/bin/vm-alpha";
          meta.description = "Run the alpha NixOS VM";
        };

        # Disabled while there is no laptop using the beta host config.
        # vmBeta = {
        #   type = "app";
        #   program = "${config.packages.vmBeta}/bin/vm-beta";
        # };
      };
    };
}
