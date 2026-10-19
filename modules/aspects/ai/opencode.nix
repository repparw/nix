{ den, ... }:
{
  den.aspects.ai.provides.opencode = {
    nixos.nixpkgs.overlays = [
      (final: _prev: {
        opencode-v2 = final.callPackage ../../_packages/opencode-v2.nix { };
      })
    ];
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        launcherPackage = pkgs.writeShellScriptBin "opencode2" ''
          exec ${pkgs.opencode-v2}/bin/opencode2 "$@"
        '';
        launcher = "${launcherPackage}/bin/opencode2";
        json5 = pkgs.python3Packages.toPythonApplication pkgs.python3Packages.json5;
      in
      {
        home.packages = [ launcherPackage ];
        home.activation.t3codeProviderCleanup = lib.hm.dag.entryBefore [ "t3codeSettingsActivation" ] (
          lib.hm.generators.mkImpureConfigMerger {
            inherit pkgs;
            format = "json";
            empty = "{}";
            jqOperation = ''
              $dynamic | del(
                .providerInstances."opencode-v2",
                .providerInstances."opencode-v2-trial",
                .providerInstances."opencode-v1"
              )
            '';
            path = "${config.home.homeDirectory}/.t3/userdata/settings.json";
            mode = "600";
            staticSettings = pkgs.writeText "t3code-provider-cleanup" "{}";
            reader = "${lib.getExe json5} --as-json";
          }
        );
        home.activation.opencodeV2DataPathMigration = lib.hm.dag.entryAfter [ "installPackages" ] ''
          data_root="$HOME/.local/share"
          old="$data_root/opencode-v2"
          new="$data_root/opencode"
          if [ -d "$old/opencode" ]; then
            if [ -e "$new" ]; then
              echo "opencode: both $old and $new exist; leaving $old untouched for manual merge." >&2
            else
              mv "$old/opencode" "$new"
              echo "opencode: moved v2 data namespace onto $new"
            fi
          fi
          rmdir "$old" 2>/dev/null || true
        '';
        xdg.configFile."opencode/plugins/nous-live.ts".source = ./opencode-plugins/nous-live-v2.ts;
        xdg.configFile."opencode/plugins/explabs-free.ts".source = ./opencode-plugins/explabs-free.ts;
        programs.opencode = {
          package = pkgs.writeShellScriptBin "opencode" ''
            exec ${lib.escapeShellArg launcher} "$@"
          '';
          enable = true;
          enableMcpIntegration = true;
          skills = { };
          web.enable = false;
          settings = {
            model = "opencode/muse-spark-1.3-contributor-free";
            small_model = "opencode/muse-spark-1.3-contributor-free";
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
              explabs = {
                npm = "@ai-sdk/openai-compatible";
                name = "Experiential Labs";
                options.baseURL = "https://api.experientiallabs.ai/api/v1";
                models = {
                  "deepseek-v4.1-flash" = {
                    name = "DeepSeek V4.1 Flash";
                  };
                };
              };
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
                  # Free-tier routes require a `user=` tag; nous-live.ts strips
                  # this key from options and injects it into request bodies.
                  nousUserTag = "user=ubritos@gmail.com";
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
        programs.t3code.userSettings.providerInstances.opencode = {
          displayName = "OpenCode 2";
          config = {
            binaryPath = lib.mkForce launcher;
            serverUrl = lib.mkForce "";
          };
        };
      };
  };
  perSystem = { config, pkgs, ... }: {
    packages.opencode-v2 = pkgs.callPackage ../../_packages/opencode-v2.nix { };
    checks.explabs-free-provider = pkgs.runCommand "check-explabs-free-provider" { } ''
      ${pkgs.nodejs}/bin/node ${../../_tests/explabs-free-provider.mjs} \
        ${config.packages.opencode-v2}/bin/opencode2 ${./opencode-plugins/explabs-free.ts}
      touch $out
    '';
  };
}
