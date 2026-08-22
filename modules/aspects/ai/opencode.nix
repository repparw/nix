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
              openrouter = {
                npm = "@ai-sdk/openai-compatible";
                name = "OpenRouter";
                options = {
                  baseURL = "https://openrouter.ai/api/v1";
                };
                models = {
                  "stealth/ox-alpha" = {
                    name = "Ox Alpha";
                  };
                };
              };
              orcarouter = {
                npm = "@ai-sdk/openai-compatible";
                name = "OrcaRouter";
                options = {
                  baseURL = "https://api.orcarouter.ai/v1";
                };
                models = {
                  "deepseek/deepseek-v4-flash-free" = {
                    name = "DeepSeek V4 Flash (Free)";
                  };
                  "deepseek/deepseek-v4-pro-free" = {
                    name = "DeepSeek V4 Pro (Free)";
                  };
                  "qwen/qwen3.8-27b-free" = {
                    name = "Qwen 3.8 27B (Free)";
                  };
                  "tencent/hy3-free" = {
                    name = "Tencent HY3 (Free)";
                  };
                  "orcarouter/free" = {
                    name = "OrcaRouter Free (Auto)";
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
