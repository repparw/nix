{ den, ... }:
{
  den.aspects.ai.provides.codex = {
    homeManager =
      { config, pkgs, ... }:
      {
        home.packages = [ pkgs.codex ];

        programs.codex = {
          enable = true;
          skills = config.programs.opencode.skills;
        };
      };
  };
}
