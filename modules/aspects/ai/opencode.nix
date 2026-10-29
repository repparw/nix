{ den, ... }:
{
  den.aspects.ai.provides.opencode = {
    nixos.nixpkgs.overlays = [
      (final: _prev: {
        opencode = final.callPackage ../../_packages/opencode.nix {
          bun = final.bun-security;
          bunForInstall = final.bun;
        };
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
        json5 = pkgs.python3Packages.toPythonApplication pkgs.python3Packages.json5;
      in
      {
        xdg.configFile."opencode/plugins/nous-live.ts".source = ./opencode-plugins/nous-live.ts;
        xdg.configFile."opencode/plugins/explabs-free.ts".source = ./opencode-plugins/explabs-free.ts;
        # Compute the opencode provider instance's hidden models at activation
        # time from the live Zen and OpenRouter catalogs. Everything is hidden
        # except: endpoints containing "free", OpenRouter's ~latest dynamic
        # slugs, and nvidia/*. Runs after the module's own $dynamic * $static
        # merge (which would replace the GUI's hiddenModels array); keeps are
        # subtracted so re-surfaced models survive later activations. Fails
        # open: a failed or empty catalog fetch leaves settings.json alone.
        # The GUI prunes stale entries when it saves.
        home.activation.t3codeModelHides = lib.hm.dag.entryAfter [ "t3codeSettingsActivation" ] (
          let
            jq = lib.getExe pkgs.jq;
            curl = lib.getExe pkgs.curl;
            json5Exe = lib.getExe json5;
          in
          ''
            settings="${config.home.homeDirectory}/.t3/userdata/settings.json"
            if [ ! -e "$settings" ]; then
              echo '{}' > "$settings"
            fi
            hides="[]"
            keeps="[]"
            z=$(${curl} -fsS -m 20 https://opencode.ai/inference/v1/models 2>/dev/null \
              | ${jq} -c '{
                  hides: [ .data[].id | select(contains("free") | not) | "opencode/" + . ],
                  keeps: [ .data[].id | select(contains("free")) | "opencode/" + . ]
                }' 2>/dev/null) || z=
            if [ -n "''${z:-}" ]; then
              hides=$(${jq} -nc --argjson a "$hides" --argjson z "$z" '$a + $z.hides') || true
              keeps=$(${jq} -nc --argjson a "$keeps" --argjson z "$z" '$a + $z.keeps') || true
            fi
            o=$(${curl} -fsS -m 30 https://openrouter.ai/api/v1/models 2>/dev/null \
              | ${jq} -c '{
                  hides: [ .data[].id | select(((contains("free")) or startswith("~") or startswith("nvidia/")) | not) | "openrouter/" + . ],
                  keeps: [ .data[].id | select((contains("free")) or startswith("~") or startswith("nvidia/")) | "openrouter/" + . ]
                }' 2>/dev/null) || o=
            if [ -n "''${o:-}" ]; then
              hides=$(${jq} -nc --argjson a "$hides" --argjson o "$o" '$a + $o.hides') || true
              keeps=$(${jq} -nc --argjson a "$keeps" --argjson o "$o" '$a + $o.keeps') || true
            fi
            if [ "$hides" != "[]" ] || [ "$keeps" != "[]" ]; then
              dynamic="$(${json5Exe} --as-json "$settings")"
              merged=$(${jq} -n \
                --argjson dynamic "$dynamic" \
                --argjson hides "$hides" \
                --argjson keeps "$keeps" \
                '$dynamic
                | .providerModelPreferences.opencode.hiddenModels = (
                    ((($dynamic.providerModelPreferences.opencode.hiddenModels // []) - $keeps) + $hides)
                    | unique
                  )') || exit 1
              printf '%s\n' "$merged" > "$settings"
            fi
          ''
        );
        programs.opencode = {
          package = pkgs.opencode;
          enable = true;
          enableMcpIntegration = true;
          mutableSettings = true;
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
  perSystem = { config, pkgs, ... }: {
    packages.opencode = pkgs.callPackage ../../_packages/opencode.nix { };
    checks.explabs-free-provider = pkgs.runCommand "check-explabs-free-provider" { } ''
      ${pkgs.nodejs}/bin/node ${../../_tests/explabs-free-provider.mjs} \
        ${config.packages.opencode}/bin/opencode ${./opencode-plugins/explabs-free.ts}
      touch $out
    '';
  };
}
