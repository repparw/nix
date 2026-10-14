{ den, ... }:
{
  # The opencode skill set is the source of truth; this aspect distributes it
  # to the other coding agents. Codex reads skills from CODEX_HOME, which T3
  # Code's codex provider shares, so the sync feeds T3 threads too.
  #
  # package = null keeps the CLI out of the profile: T3 Code's ChatGPT
  # integration launches the codex engine itself (the t3code wrappers carry
  # the nix codex on their PATH; without it T3 downloads its own managed
  # copy), and nothing else needs a user-facing binary.
  den.aspects.ai.provides.skills = {
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
