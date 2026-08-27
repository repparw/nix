{
  den,
  pkgs,
  ...
}:
{
  den.aspects.ai = {
    includes = with den.aspects.ai._; [
      mcp
      opencode
      personal-skills
      pocock-skills
      pstack
      t3code-connect
      t3code-title-patch
      t3code
    ];

    # UI/UX AI tooling: needs input and sound hardware, so it only makes
    # sense on desktop hosts. Base consumers skip this.
    provides.gui.includes = with den.aspects.ai._; [
      dictation
      speech
      voxtype-graphical-workaround
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
  };
}
