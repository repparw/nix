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
      home.packages = [
        (agent.hermesDesktop.override {
          extraEnv = {
            HERMES_DESKTOP_HERMES = "";
            HERMES_DESKTOP_IGNORE_EXISTING = "1";
          };
        })
      ];
    };
}
