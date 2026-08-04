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
        home.packages = [ pkgs.mcp-nixos ];

        programs.mcp = {
          enable = true;
          servers = {
            nixos = {
              command = "${lib.getExe pkgs.mcp-nixos}";
              args = [ ];
            };
          };
        };
      };
  };
}
