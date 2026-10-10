{
  den,
  pkgs,
  ...
}:
{
  den.aspects.ai = {
    includes = with den.aspects.ai._; [
      codex
      mcp
      opencode
      pstack
      t3code-connect
      t3code
    ];

    provides.gui.includes = with den.aspects.ai._; [
      dictation
      speech
    ];
  };
}
