{ den, ... }:
{
  den.aspects.ai.provides.opencode = {
    homeManager = {
      xdg.configFile."opencode/plugin/bedrock.ts" = {
        source = ./opencode-plugins/bedrock.ts;
      };

      xdg.configFile."opencode/plugin/nous-live.ts".text = ''
        import type { Plugin } from "@opencode-ai/plugin"
        import { readFile } from "node:fs/promises"
        import { homedir } from "node:os"
        import { join } from "node:path"

        export default (async () => ({
          config: async (cfg: any) => {
            const p = cfg.provider?.["nous-portal"]
            if (!p) return
            try {
              const authPath = join(homedir(), ".local/share/opencode/auth.json")
              const raw = await readFile(authPath, "utf8")
              const auth = JSON.parse(raw)
              const key: string | undefined = auth["nous-portal"]?.key
              if (!key) return
              const res = await fetch("https://inference-api.nousresearch.com/v1/models", {
                headers: { Authorization: "Bearer " + key },
                signal: AbortSignal.timeout(8000),
              })
              if (!res.ok) return
              const json: any = await res.json()
              const data: any[] = json.data ?? json ?? []
              if (!Array.isArray(data) || data.length === 0) return
              p.models = Object.fromEntries(
                data.map((m) => [m.id, { name: m.name ?? m.id }]),
              )
            } catch {
              // keep whatever models are already in cfg (none) on failure
            }
          },
        })) satisfies Plugin
      '';

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
          plugin = [
            "./plugin/nous-live.ts"
            "./plugin/bedrock.ts"
          ];
          permission = {
            "*" = {
              "*" = "allow";
            };
          };
          formatter = false;
          agent = {
            # PStack role agents with model mappings
            feature = {
              model = "openrouter/grok-4";
              description = "PStack feature role";
              mode = "subagent";
            };
            refactoring = {
              model = "openrouter/grok-4";
              description = "PStack refactoring role";
              mode = "subagent";
            };
            bug-fix = {
              model = "openrouter/gpt-4.5";
              description = "PStack bug-fix role";
              mode = "subagent";
            };
            perf-issue = {
              model = "openrouter/gpt-4.5";
              description = "PStack performance issue role";
              mode = "subagent";
            };
            hillclimb = {
              model = "openrouter/gpt-4.5";
              description = "PStack hillclimb role";
              mode = "subagent";
            };
            judgment-and-prose = {
              model = "openrouter/anthropic/claude-3.5-sonnet";
              description = "PStack judgment and prose role";
              mode = "subagent";
            };
            hardest-tasks = {
              model = "openrouter/anthropic/claude-3.5-sonnet";
              description = "PStack hardest tasks role";
              mode = "subagent";
            };
            how-explorer = {
              model = "openrouter/grok-4";
              description = "PStack how explorer role";
              mode = "subagent";
            };
            how-explainer = {
              model = "openrouter/anthropic/claude-3.5-sonnet";
              description = "PStack how explainer role";
              mode = "subagent";
            };
            why-investigators = {
              model = "openrouter/grok-4";
              description = "PStack why investigators role";
              mode = "subagent";
            };
            why-synthesizer = {
              model = "openrouter/anthropic/claude-3.5-sonnet";
              description = "PStack why synthesizer role";
              mode = "subagent";
            };
            reflect-tooling = {
              model = "openrouter/gpt-4.5";
              description = "PStack reflect tooling role";
              mode = "subagent";
            };
            reflect-synthesizer = {
              model = "openrouter/anthropic/claude-3.5-sonnet";
              description = "PStack reflect synthesizer role";
              mode = "subagent";
            };
            swarm-workers = {
              model = "openrouter/grok-4";
              description = "PStack swarm workers role";
              mode = "subagent";
            };
          };
          provider = {
            openrouter = {
              npm = "@ai-sdk/openai-compatible";
              name = "OpenRouter";
              options = {
                baseURL = "https://openrouter.ai/api/v1";
              };
            };
            # Nous Portal subscription routed through their OpenAI-compatible
            # inference API. Auth handled out-of-band via /connect (no key in
            # repo). Models live-fetched via ./plugin/nous-live.ts so no
            # hardcoding needed.
            nous-portal = {
              npm = "@ai-sdk/openai-compatible";
              name = "Nous Portal";
              options = {
                baseURL = "https://inference-api.nousresearch.com/v1";
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
              };
            };
          };
        };
      };
    };
  };
}
