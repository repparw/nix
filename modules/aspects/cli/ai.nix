{
  den,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  flake-file.inputs.codex-desktop-linux = {
    url = "github:ilysenko/codex-desktop-linux";
    inputs = {
      nixpkgs.follows = "nixpkgs";
      flake-utils.follows = "flake-utils";
    };
  };

  flake-file.inputs.mattpocock-skills = {
    url = "github:mattpocock/skills";
    flake = false;
  };

  den.aspects.ai = {
    includes = [ ];

    nixos =
      { ... }:
      {
        nixpkgs.overlays = [
          (final: prev: {
            codex = prev.codex.overrideAttrs (
              finalAttrs: _oldAttrs: {
                version = "0.144.1";

                src = final.fetchFromGitHub {
                  owner = "openai";
                  repo = "codex";
                  tag = "rust-v${finalAttrs.version}";
                  hash = "sha256-KHgrqIZyAmLhTZSRYbb7huBO8neOib/B1Vx/oPW2nEU=";
                };

                sourceRoot = "${finalAttrs.src.name}/codex-rs";
                cargoHash = "sha256-S4dsZXfmKvJItL2XYKyxfhqdCMATEG6oPjrtVRwkuYc=";
                cargoDeps = final.rustPlatform.fetchCargoVendor {
                  inherit (finalAttrs)
                    pname
                    version
                    src
                    sourceRoot
                    ;
                  hash = finalAttrs.cargoHash;
                };

                cargoBuildFlags = [
                  "--package"
                  "codex-cli"
                  "--package"
                  "codex-code-mode-host"
                ];
                cargoCheckFlags = [
                  "--package"
                  "codex-cli"
                  "--package"
                  "codex-code-mode-host"
                ];
              }
            );
          })
        ];
      };

    homeManager =
      {
        config,
        pkgs,
        ...
      }:
      let
        codexDesktop = inputs.codex-desktop-linux.packages.${pkgs.stdenv.hostPlatform.system}.codex-desktop;

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
          packages = [
            pkgs.codex
            codexDesktop
            pkgs.mcp-nixos
          ];
          sessionVariables.CODEX_CLI_PATH = "${pkgs.codex}/bin/codex";
          file.".codex/ds4-flash-free.config.toml".text = ''
            model = "deepseek-v4-flash-free"
            model_provider = "opencode"
            model_reasoning_effort = "minimal"
          '';
        };

        programs = {
          mcp = {
            enable = true;
            servers = {
              nixos = {
                command = "${lib.getExe pkgs.mcp-nixos}";
                args = [ ];
              };
            };
          };

          codex = {
            enable = true;
            skills = mattPocockSkills;
          };

          opencode = {
            enable = true;
            enableMcpIntegration = true;
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

        home.activation.codexOpenCodeModels = config.lib.dag.entryAfter [ "writeBoundary" ] ''
          opencode_config="${config.xdg.configHome}/opencode/opencode.json"
          opencode_auth="${config.home.homeDirectory}/.local/share/opencode/auth.json"
          codex_config="${config.home.homeDirectory}/.codex/config.toml"

          mkdir -p "$(dirname "$codex_config")"
          printf '%s\n' \
            'model_auto_compact_token_limit = 250000' \
            > "$codex_config"

          if [ -e "$opencode_auth" ] && ${lib.getExe pkgs.jq} -e 'has("opencode")' "$opencode_auth" >/dev/null; then
            printf '%s\n' \
              '[model_providers.opencode]' \
              'name = "OpenCode Zen"' \
              'base_url = "https://opencode.ai/zen/v1"' \
              'wire_api = "responses"' \
              '[model_providers.opencode.auth]' \
              "command = \"${lib.getExe pkgs.jq}\"" \
              "args = [\"-r\", \".opencode.key\", \"$opencode_auth\"]" >> "$codex_config"
          fi

          if [ -e "$opencode_auth" ] && ${lib.getExe pkgs.jq} -e 'has("opencode-go")' "$opencode_auth" >/dev/null; then
            printf '%s\n' \
              '[model_providers.opencode-go]' \
              'name = "OpenCode Go"' \
              'base_url = "https://opencode.ai/zen/go/v1"' \
              'wire_api = "responses"' \
              '[model_providers.opencode-go.auth]' \
              "command = \"${lib.getExe pkgs.jq}\"" \
              "args = [\"-r\", \".\\\"opencode-go\\\".key\", \"$opencode_auth\"]" >> "$codex_config"
          fi

          if [ -e "$opencode_config" ]; then
            ${lib.getExe pkgs.jq} -r --arg auth "$opencode_auth" '
              .provider
              | to_entries[]
              | select(.value.options.baseURL)
              | select(.key != "opencode" and .key != "opencode-go")
              | "[model_providers.\(.key)]\n"
                + "name = \"\(.value.name // .key)\"\n"
                + "base_url = \"\(.value.options.baseURL)\"\n"
                + "wire_api = \"responses\"\n"
                + "[model_providers.\(.key).auth]\n"
                + "command = \"${lib.getExe pkgs.jq}\"\n"
                + "args = " + (["-r", ".\"\(.key)\".key", $auth] | @json) + "\n"
            ' "$opencode_config" >> "$codex_config"
          fi
        '';

        systemd.user.services.t3code-web = {
          Unit = {
            Description = "T3 Code Web Service";
            After = [ "network.target" ];
          };
          Service = {
            ExecStart = "${pkgs.t3code}/bin/t3 serve --host 0.0.0.0 --port 4097 --mode web";
            Restart = "always";
            RestartSec = 5;
            Environment = [
              "T3CODE_DISABLE_PROVIDER_UPDATE_NOTIFICATIONS=1"
            ];
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
