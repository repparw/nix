{
  den,
  pkgs,
  ...
}:
{
  den.aspects.ai = {
    includes = with den.aspects.ai._; [
      dictation
      mcp
      opencode
      pocock-skills
      pstack
      speech
      t3code
    ];

    nixos =
      { config, ... }:
      {
        hardware.uinput.enable = true;

        programs.ydotool = {
          enable = true;
          group = "uinput";
        };

        users.groups.uinput.members = [ config.users.users.repparw.name ];
      };

    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.nh ];
      };
  };
}
