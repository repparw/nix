{
  den,
  inputs,
  ...
}:
{
  flake-file.inputs.mp-skills = {
    url = "github:mattpocock/skills";
    flake = false;
  };

  den.aspects.ai.provides.pocock-skills =
    let
      mpSkills =
        inputs.mp-skills or (throw "flake input `mp-skills` missing; run `nix run .#write-flake`");

      categories = [
        "engineering"
        "productivity"
      ];

      skip = [
        "tdd"
        "teach"
      ];
    in
    {
      homeManager =
        { lib, ... }:
        {
          programs.opencode.skills = lib.foldl' (
            acc: category:
            acc
            // (lib.mapAttrs'
              (name: _type: {
                inherit name;
                value = "${mpSkills}/skills/${category}/${name}";
              })
              (
                lib.filterAttrs (name: type: type == "directory" && !builtins.elem name skip) (
                  builtins.readDir "${mpSkills}/skills/${category}"
                )
              )
            )
          ) { } categories;
        };
    };
}
