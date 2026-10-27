{ inputs, ... }:
{
  den.aspects.ai.provides.hermes-desktop.homeManager =
    { pkgs, ... }:
    let
      agent = pkgs.callPackage ../../_packages/hermes-agent.nix {
        upstream = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };
    in
    {
      home.packages = [ agent.hermesDesktop ];
    };
}
