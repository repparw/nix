{
  den,
  lib,
  pkgs,
  ...
}:
{
  den.aspects.ai.provides.mcp = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [
          pkgs.mcp-nixos
          pkgs.google-cloud-sdk
        ];

        programs.mcp = {
          enable = true;
          servers = {
            nixos = {
              command = "${lib.getExe pkgs.mcp-nixos}";
              args = [ ];
            };
            stitch = {
              command = "npx";
              args = [
                "-y"
                "@keeponfirst/kof-stitch-mcp"
              ];
              env = {
                GOOGLE_CLOUD_PROJECT = "gen-lang-client-0649723761";
              };
            };
          };
        };
      };
  };
}
