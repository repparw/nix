{ den, ... }:
{
  den.aspects.ai.provides.opencode = {
    homeManager = {
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
              const free = data.filter((m) => /:free$/i.test(m.id ?? ""))
              const picked = free.length > 0 ? free : data
              p.models = Object.fromEntries(
                picked.map((m) => [m.id, { name: m.name ?? m.id }]),
              )
            } catch {
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
          model = "opencode/muse-spark-1.3-contributor-free";
          small_model = "opencode/muse-spark-1.3-contributor-free";
          plugin = [ "./plugin/nous-live.ts" ];
          permission = {
            "*" = {
              "*" = "allow";
            };
          };
          formatter = false;
          agent = {
            feature = {
              model = "opencode/muse-spark-1.2-contributor-free";
              description = "PStack feature role";
              mode = "subagent";
            };
            refactoring = {
              model = "opencode/muse-spark-1.2-contributor-free";
              description = "PStack refactoring role";
              mode = "subagent";
            };
            how-explorer = {
              model = "opencode/muse-spark-1.2-contributor-free";
              description = "PStack how explorer role";
              mode = "subagent";
            };
            why-investigators = {
              model = "opencode/muse-spark-1.2-contributor-free";
              description = "PStack why investigators role";
              mode = "subagent";
            };
            swarm-workers = {
              model = "openrouter/openrouter/free";
              description = "PStack swarm workers role";
              mode = "subagent";
            };
            swarm-workers-orca = {
              model = "orcarouter/deepseek/deepseek-v4-flash-free";
              description = "PStack swarm workers role (orca free pool arm)";
              mode = "subagent";
            };
            bug-fix = {
              model = "opencode-go/gpt-5.6-luna";
              description = "PStack bug-fix role";
              mode = "subagent";
            };
            perf-issue = {
              model = "opencode-go/gpt-5.6-luna";
              description = "PStack perf-issue role";
              mode = "subagent";
            };
            hillclimb = {
              model = "opencode-go/gpt-5.6-luna";
              description = "PStack hillclimb role";
              mode = "subagent";
            };
            reflect-tooling = {
              model = "opencode-go/gpt-5.6-luna";
              description = "PStack reflect tooling role";
              mode = "subagent";
            };
            judgment-and-prose = {
              model = "opencode-go/glm-5.3-flash";
              description = "PStack judgment and prose role";
              mode = "subagent";
            };
            hardest-tasks = {
              model = "opencode-go/glm-5.3-flash";
              description = "PStack hardest tasks role";
              mode = "subagent";
            };
            how-explainer = {
              model = "opencode-go/glm-5.3-flash";
              description = "PStack how explainer role";
              mode = "subagent";
            };
            why-synthesizer = {
              model = "opencode-go/glm-5.3-flash";
              description = "PStack why synthesizer role";
              mode = "subagent";
            };
            reflect-synthesizer = {
              model = "opencode-go/glm-5.3-flash";
              description = "PStack reflect synthesizer role";
              mode = "subagent";
            };
          };
          provider = {
            opencode = {
              blacklist = [
                # https://opencode.ai/docs/zen/
                "gpt-5-codex"
                "gpt-5.1-codex"
                "gpt-5.1-codex-max"
                "gpt-5.1-codex-mini"
                "gpt-5.2-codex"
                "claude-opus-4-1"
                "claude-sonnet-4"
                "claude-haiku-3-5"
                "gemini-3-pro"
                "minimax-m2.1"
                "minimax-m2.5"
                "glm-5"
                "glm-4.7"
                "glm-4.6"
                "kimi-k2.5"
                "kimi-k2-thinking"
                "kimi-k2"
                "qwen3-coder-480b"
                "gpt-5"
                "gpt-5.1"
                "gpt-5.2"
                "gpt-5.3-codex"
                "gpt-5.3-codex-spark"
                "gpt-5.4"
                "gpt-5.4-pro"
                "gpt-5.4-mini"
                "gpt-5.4-nano"
                "gpt-5.5"
                "gpt-5.5-pro"
                "claude-sonnet-4-5"
                "claude-opus-4-5"
                "claude-opus-4-6"
                "claude-opus-4-7"
                "claude-opus-4-8"
                "claude-sonnet-4-6"
                "claude-haiku-4-5"
                "gpt-5-nano"
                "gemini-3-flash"
                "gemini-3.1-pro"
                "gemini-3.5-flash"
                "gemini-3.5-flash-lite"
                "gemini-3.6-flash"
                "gemini-3.7-flash"
                "glm-5.1"
                "glm-5.2"
                "kimi-k2.6"
                "kimi-k2.7-code"
                "qwen3.5-plus"
                "qwen3.6-plus"
                "grok-4.5"
                "deepseek-v4-pro"
                "deepseek-v4-flash"
                "deepseek-v4-flash-vision-exp"
              ];
            };
            opencode-go = {
              blacklist = [
                "minimax-m2.5"
                "glm-5.1"
                "glm-5.2"
                "kimi-k2.6"
                "kimi-k2.7-code"
                "qwen3.6-plus"
                "qwen3.7-max"
                "qwen3.7-plus"
                "deepseek-v4-pro"
                "deepseek-v4-flash"
                "deepseek-v4-flash-vision-exp"
              ];
            };
            openrouter = {
              npm = "@ai-sdk/openai-compatible";
              name = "OpenRouter";
              options = {
                baseURL = "https://openrouter.ai/api/v1";
              };
              whitelist = [
                "~z-ai/glm-flash-latest"
                "deepseek/deepseek-v4.1-flash"
                "openrouter/free"
              ];
              models = {
                # OpenRouter has no `:z-ai` model-id suffix; `provider.only`
                # is the request-body pin. `:floor` sorts by list price and
                # admits non-Z.AI providers that match Z.AI's list price.
                "~z-ai/glm-flash-latest" = {
                  name = "GLM Flash Latest (Z.ai)";
                  options = {
                    provider = {
                      only = [ "z-ai" ];
                    };
                  };
                };
                "deepseek/deepseek-v4.1-flash" = {
                  name = "DeepSeek V4.1 Flash (DeepSeek)";
                  options = {
                    provider = {
                      only = [ "deepseek" ];
                    };
                  };
                };
                # OpenRouter: base slug "openai" does not match tier endpoints;
                # `openai/flex` is required.
                "openai/gpt-5.6-luna" = {
                  name = "GPT 5.6 Luna (OpenAI Flex)";
                  options = {
                    provider = {
                      only = [ "openai/flex" ];
                    };
                  };
                };
              };
            };
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
