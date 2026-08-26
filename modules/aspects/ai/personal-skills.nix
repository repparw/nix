{
  den,
  ...
}:
# Personal skills authored in this repo, exposed to opencode.
# Upstream skills from flake inputs live in pocock-skills.nix / pstack.nix;
# name collisions there win over these.
{
  den.aspects.ai.provides.personal-skills =
    { ... }:
    {
      homeManager =
        { ... }:
        {
          programs.opencode.skills.watch-upstream = ./skills/watch-upstream;
        };
    };
}
