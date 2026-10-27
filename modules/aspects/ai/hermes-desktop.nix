{ inputs, ... }:
{
  den.aspects.hermes-desktop.nixos =
    { pkgs, ... }:
    let
      agent = pkgs.callPackage ../../_packages/hermes-agent.nix {
        upstream = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };
    in
    {
      home-manager.sharedModules = [
        {
          home.packages = [ agent.hermesDesktop ];
        }
      ];
    };
}
