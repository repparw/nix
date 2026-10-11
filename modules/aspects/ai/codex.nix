{ den, ... }:
{
  # T3 Code's ChatGPT integration installs and updates its own managed Codex
  # engine (and the wrapper PATHs in t3code-*.nix no longer pin the nix CLI),
  # so only the CODEX_HOME file management stays declarative here.
  den.aspects.ai.provides.codex = {
    homeManager =
      { config, ... }:
      {
        programs.codex = {
          enable = true;
          package = null;
          skills = config.programs.opencode.skills;
        };
      };
  };
}
