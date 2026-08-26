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
      # Guarded so `nix run .#write-flake` can collect the flake-file
      # declaration before the input exists in the generated flake.
      mpSkills =
        inputs.mp-skills or (throw "flake input `mp-skills` missing; run `nix run .#write-flake`");

      categories = [
        "engineering"
        "productivity"
      ];

      # Name collisions with pstack skills; pstack wins.
      # To prefer the mattpocock variant instead, remove the name here.
      # (`prototype` is NOT a collision: pstack ships it as a poteto-mode
      # playbook, not as a standalone skill.)
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
