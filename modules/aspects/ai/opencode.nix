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
          plugin = [ "./plugin/nous-live.ts" ];
          permission = {
            "*" = {
              "*" = "allow";
            };
          };
          formatter = false;
          agent = {
            # pStack role agents. Models mirror ~/.cursor/rules/pstack-models.mdc
            # go quota most→least: muse-spark, dsv4-flash, glm-5.3-flash, luna.
            # Volume + swarm on zen/orca free; luna only on gpt-reasoning roles.
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
            openrouter = {
              npm = "@ai-sdk/openai-compatible";
              name = "OpenRouter";
              options = {
                baseURL = "https://openrouter.ai/api/v1";
              };
              models = {
                # Pin GLM Flash (latest alias) to the z-ai provider. OpenRouter has
                # no `:z-ai` model-id suffix (only :free/:floor/:nitro/:exacto), and
                # the `~z-ai/glm-flash-latest` router alias honors the request-body
                # `provider` field (verified: default routing → GMICloud, with the
                # body → Z.AI). model `options` map to providerOptions.openaiCompatible
                # which the SDK merges into the body, so `provider.only: ["z-ai"]`
                # reaches OpenRouter and pins routing to Z.AI's endpoint.
                # Deliberately NOT `:floor`: that sorts by *list* price, so it also
                # admits providers price-matching Z.AI at list, missing Z.AI's 50%
                # effective discount and better cache-hit rate.
                "~z-ai/glm-flash-latest" = {
                  name = "GLM Flash Latest (Z.ai)";
                  options = {
                    provider = {
                      only = [ "z-ai" ];
                    };
                  };
                };
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
