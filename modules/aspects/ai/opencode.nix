{ den, ... }:
{
  den.aspects.ai.provides.opencode = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.opencode-desktop ];

        programs.opencode = {
          enable = true;
          enableMcpIntegration = true;
          skills = { };
          web = {
            enable = true;
            extraArgs = [
              "--port"
              "4096"
            ];
          };
          settings = {
            permission = {
              "*" = {
                "*" = "allow";
              };
            };
            formatter = false;
            provider = {
              oc-galo = {
                npm = "@ai-sdk/openai-compatible";
                name = "oc-galo";
                options = {
                  baseURL = "https://opencode.ai/zen/go/v1";
                };
                models = {
                  deepseek-v4-flash = {
                    name = "DeepSeek V4 Flash";
                  };
                  deepseek-v4-pro = {
                    name = "DeepSeek V4 Pro";
                  };
                  "kimi-k2.6" = {
                    name = "Kimi K2.6";
                  };
                };
              };
            };
            agent = {
              build = {
                prompt = ''
                  You are the project lead. For each request:

                  1. Decompose it into self-contained steps.
                  2. Delegate each step to a subagent (general or explore) via
                     the task tool, in parallel when independent.
                  3. Run exploration and implementation inside subagent child
                     sessions so the main thread stays clean; integrate their
                     results here rather than redoing the work.
                  4. Verify each subagent's result, then report a concise answer.
                '';
              };
              general = {
                permission = {
                  task = "deny";
                };
              };
              explore = {
                permission = {
                  task = "deny";
                };
              };
            };
          };
        };
      };
  };
}
