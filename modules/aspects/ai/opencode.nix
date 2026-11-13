{ den, ... }:
{
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
        # time from the models.dev catalog (the catalog OpenCode itself uses).
        # The rules live in opencode-model-hides.jq: legacy models are hidden
        # per provider/family, paid models are hidden from the free-inference
        # providers, groq and opencode-go are dropped, and Cloudflare hides
        # only its paid-only blacklist. Runs after the module's own
        # $dynamic * $static merge (which would replace the GUI's
        # hiddenModels array); keeps are subtracted so re-surfaced models
        # survive later activations. Fails open: a failed or empty catalog
        # fetch leaves settings.json alone. The GUI prunes stale entries when
        # it saves.
        home.activation.t3codeModelHides = lib.hm.dag.entryAfter [ "t3codeSettingsActivation" ] (
          let
            jq = lib.getExe pkgs.jq;
            curl = lib.getExe pkgs.curl;
            json5Exe = lib.getExe json5;
            modelHidesJq = pkgs.writeText "opencode-model-hides.jq" (
              builtins.readFile ./opencode-model-hides.jq
            );
          in
          ''
            settings="${config.home.homeDirectory}/.t3/userdata/settings.json"
            if [ ! -e "$settings" ]; then
              echo '{}' > "$settings"
            fi
            result=$(${curl} -fsS -m 60 https://models.dev/api.json 2>/dev/null \
              | ${jq} -c -f ${modelHidesJq} 2>/dev/null) || result=
            if [ -n "''${result:-}" ]; then
              dynamic="$(${json5Exe} --as-json "$settings")"
              merged=$(${jq} -n \
                --argjson dynamic "$dynamic" \
                --argjson result "$result" \
                '$dynamic
                | .providerModelPreferences.opencode.hiddenModels = (
                    ((($dynamic.providerModelPreferences.opencode.hiddenModels // []) - $result.keeps) + $result.hides)
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
              "browse_*" = {
                "*" = "ask";
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
