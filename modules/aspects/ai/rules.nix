{ den, ... }:
{
  den.aspects.ai.provides.rules = {
    homeManager =
      let
        base = ''
          ## Tooling

          When an expected tool, CLI, MCP, or integration is missing or broken, flag it explicitly to the user. Never silently swallow the failure, work around it quietly, or push the check back to the user as if you never had access.
        '';

        prose = ''
          ## Communication

          Write direct, concrete prose. Name mechanisms and observable results instead of abstract claims. Skip filler, flattery, em dashes, and decorative formatting. Use short paragraphs, complete sentences, and lists when comparing items.

          For substantial docs, PR descriptions, or issue reports, read `~/.agents/skills/unslop/SKILL.md` and apply it without touching code, commands, or quotes. For agent instructions, skills, or `AGENTS.md`, use the `writing-for-agents` skill.
        '';

        opencodeAndCodex = "${base}\n${prose}";
        antigravity = ''
          ---
          trigger: always_on
          ---

        ''
        + base;
      in
      {
        xdg.configFile."opencode/AGENTS.md".text = opencodeAndCodex;
        xdg.configFile."codex/AGENTS.md".text = opencodeAndCodex;
        home.file.".gemini/config/rules/global.md".text = antigravity;
      };
  };
}
