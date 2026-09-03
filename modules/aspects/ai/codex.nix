{ den, ... }:
{
  den.aspects.ai.provides.codex = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.codex ];

        programs.codex = {
          enable = true;
          skills = { };
        };
      };
  };
}
