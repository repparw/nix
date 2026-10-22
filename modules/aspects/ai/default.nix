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
      pstack
      skills
      t3code-browser-libs
      t3code-connect
      t3code
    ];

    provides.gui.includes = with den.aspects.ai._; [
      dictation
      speech
    ];
  };
}
