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
      personal-skills
      pocock-skills
      pstack
      t3code-connect
      t3code
    ];

    provides.gui.includes = with den.aspects.ai._; [
      dictation
      speech
      voxtype-graphical-workaround
    ];
  };
}
