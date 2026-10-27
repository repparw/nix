{ inputs, ... }:
{
  den.aspects.hermes-desktop.nixos =
    { pkgs, ... }:
    {
      home-manager.sharedModules = [
        {
          home.packages = [ inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.desktop ];
        }
      ];
    };
}
