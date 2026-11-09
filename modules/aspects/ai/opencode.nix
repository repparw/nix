{ den, ... }:
{
  # Packaged by nixpkgs (the channel and pin both track the anomalyco v2
  # release); the vendored 2.0.26 workaround was retired per issue #229.
  den.aspects.ai.provides.opencode = {
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
        # Plugins are live state in ~/.config/opencode/plugins/ (seeded by
        # hand from the repo history during the live-state migration); the
        # runtime providers (nous-portal, explabs, orcarouter) and the
        # session default model come from those plugins.
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
              | ${jq} -c '
                  # NVIDIA publishes both paid and :free variants. Only surface
                  # the free variant when its input and output prices are zero.
                  def keep:
                    (.id | startswith("~"))
                    or ((.id | startswith("nvidia/"))
                        and (.id | endswith(":free"))
                        and ((.pricing.prompt | tonumber?) == 0)
                        and ((.pricing.completion | tonumber?) == 0))
                    or ((.id | startswith("nvidia/") | not) and (.id | contains("free")));
                  {
                    hides: [ .data[] | select(keep | not) | "openrouter/" + .id ],
                    keeps: [ .data[] | select(keep) | "openrouter/" + .id ]
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
            # small_model has no plugin surface (the runtime derives it from
            # model families), so it stays the one declared model setting;
            # everything else model-related is runtime state: the session
            # default comes from model-defaults.ts, and providers are
            # registered by their plugins (nous-live, explabs-free,
            # orca-router) — see those files.
            small_model = "opencode/muse-spark-1.3-contributor-free";
            # GitHub Student/Free Copilot plans only allow Auto model
            # selection; this plugin adds the github-copilot/auto router
            # models so the Copilot provider lists anything at all.
            plugins = [
              "@klconsultancy/opencode-copilot-auto@1.0.1"
            ];
            permission = {
              "*" = {
                "*" = "allow";
              };
            };
            formatter = false;
          };
        };
      };
  };
  perSystem = { config, pkgs, ... }: {
    packages.opencode = pkgs.opencode;
  };
}
