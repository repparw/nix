{ den, pkgs, ... }:
{
  den.aspects.ai.provides.codex = {
    homeManager = {
      home.packages = [ pkgs.codex ];

      programs.codex = {
        enable = true;
        skills = { };
      };
    };
  };
}
