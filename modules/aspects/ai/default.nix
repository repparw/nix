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
      rules
      skills
      t3code
    ];

    provides.gui.includes = with den.aspects.ai._; [
      hermes-desktop
      dictation
      speech
    ];
  };
}
