{
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    (inputs.git-hooks.flakeModule or { })
  ];

  perSystem =
    { config, pkgs, ... }:
    {
      pre-commit = {
        settings = {
          hooks = {
            nixfmt = {
              enable = true;
              package = pkgs.nixfmt;
            };
            deadnix = {
              enable = true;
              args = [
                "--edit"
                "--no-lambda-arg"
                "--no-lambda-pattern-names"
              ];
            };
            shellcheck = {
              enable = true;
              types_or = [
                "shell"
                "bash"
              ];
            };
            write-flake = {
              enable = true;
              name = "write-flake";
              entry = "${pkgs.lib.getExe (
                pkgs.writeShellApplication {
                  name = "write-flake-hook";
                  runtimeInputs = [
                    pkgs.nix
                    pkgs.git
                  ];
                  text = ''
                    set -euo pipefail
                    cd "$(git rev-parse --show-toplevel)"
                    if nix --extra-experimental-features 'nix-command flakes' run .#write-flake 2>/dev/null; then
                      git add flake.nix
                    else
                      echo "write-flake: failed to run nix (offline sandbox?). Skipping flake.nix regeneration."
                    fi
                  '';
                }
              )}";
              language = "system";
              pass_filenames = false;
              files = "\\.nix$";
            };
          };
        };
      };

      devShells.default = pkgs.mkShell {
        nativeBuildInputs = [ config.pre-commit.settings.package ];
        shellHook = config.pre-commit.installationScript;
      };
    };
}
