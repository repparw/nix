{
  den,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  flake-file.inputs.mattpocock-skills = {
    url = "github:mattpocock/skills";
    flake = false;
  };

  den.aspects.ai = {
    includes = [ ];

    homeManager =
      {
        config,
        pkgs,
        ...
      }:
      let
        skillFiles = lib.filter (
          path:
          let
            pathString = toString path;
          in
          baseNameOf pathString == "SKILL.md"
          && !(lib.hasInfix "/deprecated/" pathString)
          && !(lib.hasInfix "/node_modules/" pathString)
        ) (lib.filesystem.listFilesRecursive (inputs.mattpocock-skills + "/skills"));

        mattPocockSkills = lib.listToAttrs (
          map (skillFile: {
            name = builtins.unsafeDiscardStringContext (baseNameOf (dirOf (toString skillFile)));
            value = dirOf (toString skillFile);
          }) skillFiles
        );
      in
      {
        home = {
          packages = [ pkgs.codex ];
          sessionVariables.CODEX_CLI_PATH = "${pkgs.codex}/bin/codex";
        };

        programs = {
          codex = {
            enable = true;
            skills = mattPocockSkills;
          };

          opencode = {
            enable = true;
            skills = mattPocockSkills;
            settings = {
              permission = {
                "*" = {
                  "*" = "allow";
                };
              };
              formatter = false;
              provider = {
                oc-galo = {
                  npm = "@ai-sdk/openai-compatible";
                  name = "oc-galo";
                  options = {
                    baseURL = "https://opencode.ai/zen/go/v1";
                  };
                  models = {
                    deepseek-v4-flash = {
                      name = "DeepSeek V4 Flash";
                    };
                    deepseek-v4-pro = {
                      name = "DeepSeek V4 Pro";
                    };
                    "kimi-k2.6" = {
                      name = "Kimi K2.6";
                    };
                  };
                };
              };
            };
          };

          t3code.enable = true;
        };

        systemd.user.services.t3code-web = {
          Unit = {
            Description = "T3 Code Web Service";
            After = [ "network.target" ];
          };
          Service = {
            ExecStart = "${pkgs.t3code}/bin/t3code serve --host 0.0.0.0 --port 4097 --mode web";
            Restart = "always";
            RestartSec = 5;
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
        };

        # systemd.user.services.opencode-web = {
        #   Unit = {
        #     After = [ "graphical-session.target" ];
        #     Wants = [ "graphical-session.target" ];
        #   };
        #   Service.Environment = [
        #     "PATH=/run/wrappers/bin:${config.home.homeDirectory}/.nix-profile/bin:/nix/profile/bin:${config.home.homeDirectory}/.local/state/nix/profile/bin:/etc/profiles/per-user/${config.home.username}/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
        #     "SUDO_ASKPASS=${pkgs.openssh-askpass}/libexec/gtk-ssh-askpass"
        #   ];
        # };
      };
  };
}
