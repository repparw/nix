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
              entry = "${pkgs.writeShellScript "write-flake-hook" ''
                set -euo pipefail
                cd "$(git rev-parse --show-toplevel)"

                mapfile -t staged_nix_files < <(git diff --cached --name-only --diff-filter=ACMR -- '*.nix')

                if [[ ''${#staged_nix_files[@]} -eq 0 ]]; then
                  exit 0
                fi

                for path in "''${staged_nix_files[@]}"; do
                  if git diff --cached --unified=0 -- "$path" | grep -qE '^[+-].*flake-file\.inputs'; then
                    echo "pre-commit: regenerating flake.nix from flake-file inputs"
                    nix run .#write-flake
                    git add flake.nix
                    exit 0
                  fi
                done

                exit 0
              ''}";
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
