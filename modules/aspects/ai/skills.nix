{
  den,
  inputs,
  lib,
  ...
}:
{
  flake-file.inputs.cursor-plugins = {
    url = "github:cursor/plugins";
    flake = false;
  };
  flake-file.inputs.mattpocock-skills = {
    url = "github:mattpocock/skills";
    flake = false;
  };

  den.aspects.ai.provides.skills =
    let
      plugins =
        inputs.cursor-plugins
          or (throw "flake input `cursor-plugins` missing; run `nix run .#write-flake`");
    in
    {
      homeManager =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          skillsDir = "${plugins}/pstack/skills";
          teamSkill = name: "${plugins}/cursor-team-kit/skills/${name}";
          excludedSkills = [
            "make-bot-ui"
            "poteto-help"
            "reflect"
            "setup-pstack"
          ];
          pstackEntries = builtins.readDir skillsDir;
          principleNames = builtins.attrNames (
            lib.filterAttrs (name: type: type == "directory" && lib.hasPrefix "principle-" name) pstackEntries
          );
          potetoModeSkill = pkgs.runCommand "pstack-poteto-mode-skill" { } ''
            cp -r ${skillsDir}/poteto-mode "$out"
            chmod -R u+w "$out"
            mkdir -p "$out/references"
            ${lib.concatMapStringsSep "\n" (name: ''
              cp -r ${skillsDir}/${name} "$out/references/${name}"
            '') principleNames}
            ${lib.getExe pkgs.python3} - "$out/SKILL.md" <<'PY'
            import pathlib, sys

            path = pathlib.Path(sys.argv[1])
            text = path.read_text()
            old = "Read the leaf skill in full for any principle you apply. Each entry names when it applies. Each leaf is the **principle-<title>** skill"
            new = "Read the leaf reference in full for any principle you apply. Each entry names when it applies. Each leaf lives at `references/principle-<title>/SKILL.md` inside this skill's folder"
            assert old in text, "expected Principles pointer line in poteto-mode/SKILL.md"
            path.write_text(text.replace(old, new, 1))
            PY
          '';
          pocockSource = inputs.mattpocock-skills;
          noCommentsSource = pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/backnotprop/pstack/25abb38559ddbabec563646224d09eff9a250eca/skills/no-comments/SKILL.md";
            hash = "sha256-pyUFl3HRV3/Fn70mbi91/n9UeiOj3MEFJFnbVK4QwMI=";
          };
          noCommentsReference = pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/backnotprop/pstack/25abb38559ddbabec563646224d09eff9a250eca/skills/no-comments/references/comment-sicko.md";
            hash = "sha256-c8C8uMJYmBExwA8JwsVuMAxyJYA71OEJPvQTYuAHPZg=";
          };
          noCommentsSkill = pkgs.runCommand "pstack-no-comments-skill" { } ''
            mkdir -p "$out/references"
            cp ${noCommentsSource} "$out/SKILL.md"
            cp ${noCommentsReference} "$out/references/comment-sicko.md"
          '';
        in
        {
          programs.codex = {
            enable = true;
            package = null;
            enableMcpIntegration = true;
            mutableSettings = true;
          };

          home.file =
            lib.mapAttrs' (name: source: lib.nameValuePair ".agents/skills/${name}" { inherit source; }) (
              lib.mapAttrs (name: _: skillsDir + "/${name}") (
                lib.filterAttrs (
                  name: type:
                  type == "directory"
                  && !(builtins.elem name excludedSkills)
                  && !(lib.hasPrefix "principle-" name)
                  && name != "poteto-mode"
                ) pstackEntries
              )
              // {
                poteto-mode = "${potetoModeSkill}";
                deslop = teamSkill "deslop";
                no-comments = "${noCommentsSkill}";
                control-cli = teamSkill "control-cli";
                control-ui = teamSkill "control-ui";
                retro = "${pocockSource}/skills/engineering/retro";
                writing-for-agents = "${pocockSource}/skills/productivity/writing-for-agents";
                diagnosing-bugs = "${pocockSource}/skills/engineering/diagnosing-bugs";
                pr = "${pocockSource}/skills/engineering/pr";
              }
            )
            // {
              ".gemini/config/skills".source =
                config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agents/skills";
            };
        };
    };

  perSystem =
    { pkgs, ... }:
    {
      checks = lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        ai-skills-and-gws =
          let
            alphaHome = inputs.self.nixosConfigurations.alpha.config.home-manager.users.repparw;
            skillFiles = builtins.attrNames (
              lib.filterAttrs (k: _: lib.hasPrefix ".agents/skills/" k) alphaHome.home.file
            );
            topLevelPrinciples = builtins.filter (lib.hasPrefix ".agents/skills/principle-") skillFiles;
            potetoSource = alphaHome.home.file.".agents/skills/poteto-mode".source;
            hasGws = builtins.any (p: (p.pname or "") == "gws") alphaHome.home.packages;
          in
          pkgs.runCommand "check-ai-skills-and-gws" { } ''
            test "${toString (builtins.length topLevelPrinciples)}" = "0"
            test "${if hasGws then "yes" else "no"}" = "yes"
            test -f "${potetoSource}/SKILL.md"
            grep -Fq 'references/principle-<title>/SKILL.md' "${potetoSource}/SKILL.md"
            count=$(find "${potetoSource}/references" -maxdepth 2 -name SKILL.md | wc -l)
            test "$count" -ge 20
            echo "Verified: 0 top-level principle-* skills, $count folded under poteto-mode/references, pkgs.gws present"
            touch "$out"
          '';
      };
    };
}
