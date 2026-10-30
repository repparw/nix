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
    let
      agentDocsPython = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
      worktreeBootstrap = pkgs.writeShellScript "nix-worktree-bootstrap" ''
        # Managed by modules/git-hooks.nix: worktree bootstrap
        set -euo pipefail
        if [ "''${3:-0}" != 1 ] || [ ! -f flake.nix ] || [ -f .pre-commit-config.yaml ]; then
          exit 0
        fi

        while IFS= read -r variable; do
          unset "$variable"
        done < <(${pkgs.lib.getExe pkgs.git} rev-parse --local-env-vars)

        echo "Initializing Nix worktree Git hooks in $PWD" >&2
        if ! ${pkgs.lib.getExe pkgs.nix} develop --no-update-lock-file --command true; then
          echo "Worktree created, but hook setup failed. Retry: nix develop --no-update-lock-file --command true" >&2
          exit 1
        fi
        test -f .pre-commit-config.yaml
      '';
    in
    {
      pre-commit = {
        settings = {
          hooks = {
            convco = {
              enable = true;
              entry = pkgs.lib.getExe (
                pkgs.writeShellApplication {
                  name = "convco-hook";
                  text = ''
                    message_file="$1"
                    IFS= read -r subject < "$message_file" || true

                    case "$subject" in
                      flake.lock:\ Update | fixup\!\ * | squash\!\ * | amend\!\ * | Merge\ * | Revert\ \"*)
                        exit 0
                        ;;
                    esac

                    ${pkgs.lib.getExe pkgs.convco} check --from-stdin < "$message_file"
                  '';
                }
              );
            };
            # Keep Markdown changes aligned with the treefmt CI check.
            prettier = {
              enable = true;
              files = "\\.md$";
            };
            # Surface broken agent-doc links before CI, without Nix evaluation.
            agent-docs = {
              enable = true;
              name = "agent-docs";
              entry = "${pkgs.lib.getExe agentDocsPython} ${./scripts/check-agent-docs.py} .";
              language = "system";
              pass_filenames = false;
              files = "^(AGENTS\\.md|docs/.*\\.md|\\.agents/.*\\.md|modules/scripts/check-agent-docs(\\.test)?\\.py)$";
            };
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
        nativeBuildInputs = [
          config.pre-commit.settings.package
          # OpenTofu manages the OCI cloud resources in infra/.
          pkgs.opentofu
        ];
        shellHook = ''
          ${config.pre-commit.installationScript}
          if repo_hooks_common_dir="$(${pkgs.lib.getExe pkgs.git} rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
            ${pkgs.lib.getExe pkgs.git} config --local core.hooksPath "$repo_hooks_common_dir/hooks"
            repo_post_checkout="$repo_hooks_common_dir/hooks/post-checkout"
            if { [ ! -e "$repo_post_checkout" ] && [ ! -L "$repo_post_checkout" ]; } || ${pkgs.lib.getExe pkgs.gnugrep} -qFx '# Managed by modules/git-hooks.nix: worktree bootstrap' "$repo_post_checkout"; then
              ${pkgs.lib.getExe' pkgs.nix "nix-store"} --add-root "$repo_post_checkout" --indirect --realise ${worktreeBootstrap} >/dev/null
            else
              echo "Preserving existing post-checkout hook: $repo_post_checkout" >&2
            fi
          fi
        '';
      };
    };
}
