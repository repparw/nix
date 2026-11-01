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
      skills
      t3code-browser-libs
      t3code-connect
      t3code
    ];

    provides.gui.includes = with den.aspects.ai._; [
      hermes-desktop
      dictation
      speech
    ];
  };
}
