{ den, inputs, ... }:
{
  flake-file.inputs.mattpocock-skills = {
    url = "github:mattpocock/skills";
    flake = false;
  };

  den.aspects.ai.provides.mattpocock-skills = {
    homeManager =
      { pkgs, ... }:
      let
        source = pkgs.applyPatches {
          name = "mattpocock-skills";
          src = inputs.mattpocock-skills;
          patches = [ ./patches/mattpocock-skills.patch ];
        };
      in
      {
        programs.opencode.skills = {
          retro = "${source}/skills/engineering/retro";
          writing-for-agents = "${source}/skills/productivity/writing-for-agents";
          diagnosing-bugs = "${source}/skills/engineering/diagnosing-bugs";
        };
      };
  };
}
