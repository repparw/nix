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
              // Paid Nous models (383 in catalog) stay out of the picker:
              // keep the :free endpoints only (e.g.
              // stepfun/step-3.7-flash:free). If none match, keep the full
              // list rather than wiping the provider.
              const free = data.filter((m) => /:free$/i.test(m.id ?? ""))
              const picked = free.length > 0 ? free : data
              p.models = Object.fromEntries(
                picked.map((m) => [m.id, { name: m.name ?? m.id }]),
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
          # New-session default (picker fallback was the stale ox-alpha
          # endpoint, since renamed to glm-5.3-flash). Zen Muse Spark 1.3
          # free tier. small_model moves title generation off the old
          # gpt-5-nano default onto the same free tier.
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
            # Stale-endpoint hiding for the t3code picker. t3code's opencode
            # driver talks to opencode-web on :4096, so the full Zen/Go
            # catalog shows up in its model list. Policy (2026-09-12,
            # verified against live https://opencode.ai/zen/v1/models):
            # GPT keep 5.6+, Anthropic keep 5+, other families latest
            # generation only, DeepSeek via the 4.1 endpoints (Go/OpenRouter)
            # only. Free endpoints (*-free) are never listed here.
            opencode = {
              blacklist = [
                # Zen deprecated table (https://opencode.ai/docs/zen/).
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
                # Released before the 6mo cutoff (2026-03-12).
                "gpt-5" # 2025-08-07
                "gpt-5.1" # 2025-11-12
                "gpt-5.2" # 2025-12-11
                "gpt-5.3-codex" # predates GPT-5.4 (2026-03-05)
                "gpt-5.3-codex-spark" # same generation
                "gpt-5.4" # 2026-03-05
                "gpt-5.4-pro" # same generation
                "gpt-5.4-mini" # same generation
                "gpt-5.4-nano" # same generation
                "gpt-5.5" # 2026-04-23, superseded by 5.6 (keep 5.6+)
                "gpt-5.5-pro" # same generation
                "claude-sonnet-4-5" # 2025-09-29
                "claude-opus-4-5" # 2025-11-01
                "claude-opus-4-6" # superseded by Opus 5 (keep 5+)
                "claude-opus-4-7" # same generation
                "claude-opus-4-8" # same generation
                "claude-sonnet-4-6" # superseded by Sonnet 5 (keep 5+)
                "claude-haiku-4-5" # no Haiku 5 in catalog; strict 5+
                "gpt-5-nano" # superseded; small_model moved to free tier
                # Latest-generation-only per family (keep the newest line).
                "gemini-3-flash" # keep 3.8-flash
                "gemini-3.1-pro"
                "gemini-3.5-flash"
                "gemini-3.5-flash-lite"
                "gemini-3.6-flash"
                "gemini-3.7-flash"
                "glm-5.1" # keep 5.3 + 5.3-flash
                "glm-5.2" # same (released 2026-06-16, superseded 08-26)
                "kimi-k2.6" # keep k3
                "kimi-k2.7-code" # same (coding specialist, superseded by k3)
                "qwen3.5-plus" # keep 3.7-max + 3.7-plus
                "qwen3.6-plus" # same
                "grok-4.5" # keep 4.6 (+ build-0.1, separate product)
                # DeepSeek: Zen has no 4.1 ID; all three serve pre-4.1 or
                # alias to it. Use opencode-go/openrouter 4.1 endpoints.
                "deepseek-v4-pro"
                "deepseek-v4-flash"
                "deepseek-v4-flash-vision-exp"
              ];
            };
            # Go catalog mirrors the Zen generation cuts (same model IDs).
            opencode-go = {
              blacklist = [
                "minimax-m2.5" # deprecated upstream 2026-08-05
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
              # Hide the rest of the OpenRouter catalog; only the pinned models
              # below plus the free variant stay selectable.
              whitelist = [
                "~z-ai/glm-flash-latest"
                "deepseek/deepseek-v4.1-flash"
                "openrouter/free"
              ];
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
                # Same treatment: DeepSeek's own endpoint is cheapest on input,
                # output, and cache reads (half of Novita/DeepInfra),
                # so pin to the `deepseek` provider.
                "deepseek/deepseek-v4.1-flash" = {
                  name = "DeepSeek V4.1 Flash (DeepSeek)";
                  options = {
                    provider = {
                      only = [ "deepseek" ];
                    };
                  };
                };
                # Pin Luna to OpenAI's flex tier endpoint. Same mechanism as
                # the Z.AI pin above: model `options` map to
                # providerOptions.openaiCompatible which the SDK merges into
                # the request body, so `provider.only: ["openai/flex"]`
                # reaches OpenRouter and restricts routing to the flex
                # endpoint (50% discount, higher latency, no fallback to
                # default tier). Base slug "openai" would NOT match tier
                # endpoints — explicit `openai/flex` opt-in is required.
                # NOTE: currently hidden by the provider `whitelist` above;
                # add "openai/gpt-5.6-luna" there to re-enable.
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
