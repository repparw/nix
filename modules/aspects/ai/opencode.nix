{ den, ... }:
{
  den.aspects.ai.provides.opencode = {
    nixos.nixpkgs.overlays = [
      (final: _prev: {
        opencode-v2 = final.callPackage ../../_packages/opencode-v2.nix { };
      })
    ];
    homeManager =
      { pkgs, ... }:
      {
        xdg.configFile."opencode/plugins/nous-live.ts".source = ./opencode-plugins/nous-live-v2.ts;
        programs.opencode = {
          package = pkgs.opencode-v2;
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
      };
  };
  perSystem = { pkgs, ... }: {
    packages.opencode-v2 = pkgs.callPackage ../../_packages/opencode-v2.nix { };
  };
}
