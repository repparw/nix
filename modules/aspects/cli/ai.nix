{
  den,
  inputs,
  pkgs,
  ...
}:
{
  den.aspects.ai = {
    includes = [ ];

    homeManager =
      { config, ... }:
      {
        imports = [ inputs.codex-desktop-linux.homeManagerModules.default ];

        home.sessionVariables.CODEX_CLI_PATH = "${config.programs.codex.package}/bin/codex";

        programs = {
          codex = {
            enable = true;
            settings = {
              approval_policy = "never";
              sandbox_mode = "danger-full-access";
            };
          };

          codexDesktopLinux = {
            enable = true;
            computerUseUi.enable = true;
            remoteMobileControl.enable = true;
            remoteControl.enable = true;
          };

          opencode = {
            enable = true;
            web = {
              enable = true;
              extraArgs = [
                "--hostname"
                "0.0.0.0"
                "--port"
                "4096"
              ];
            };
            skills = {
              commit = ''
                ---
                name: conventional-commit
                description: Add and commit changes using conventional commits
                ---

                Create git commits for the current changes using the Conventional Commits standard.

                ## Context

                Based on the conversation, determine what context is relevant for the commit message. If the user provided specific guidance about what to commit or the commit message, use that. Otherwise, analyze the changes to determine an appropriate commit message. If the changes to commit are not related, you can split them into multiple commits.

                ## Process

                1. **Analyze the changes** by running:
                   - `git status` to see all modified/untracked files
                   - `git diff` to see unstaged changes
                   - `git diff --staged` to see already-staged changes
                   - `git log --oneline -5` to see recent commit style

                2. **Stage appropriate files**:
                   - Stage all related changes with `git add`
                   - Do NOT stage files that appear to contain secrets (.env, credentials, API keys, tokens)
                   - If you detect potential secrets, warn the user and skip those files

                3. **Determine the commit type** based on the changes:
                   - `feat`: New feature or capability
                   - `fix`: Bug fix
                   - `docs`: Documentation only
                   - `style`: Formatting, whitespace (not CSS)
                   - `refactor`: Code restructuring without behavior change
                   - `perf`: Performance improvement
                   - `test`: Adding or updating tests
                   - `build`: Build system or dependencies
                   - `ci`: CI/CD configuration
                   - `chore`: Maintenance tasks, tooling, config

                4. **Determine the scope** (optional):
                   - Use a short identifier for the affected area: `feat(parser):`, `fix(api):`
                   - Omit scope if changes are broad or scope is unclear

                5. **Write the commit message**:
                   - **Subject line**: `<type>[optional scope]: <description>`
                     - Use imperative mood ("add" not "added")
                     - Lowercase, no period at end
                     - Max 50 characters if possible, 72 hard limit
                   - **Body** (if needed): Explain _why_, not _what_
                     - Wrap at 72 characters
                     - Separate from subject with blank line

                ## Commit Format

                ```
                <type>[scope]: <subject>

                [optional body explaining WHY this change was made]
                ```

                ## Examples

                Simple change:

                ```
                fix(parser): handle empty input without throwing
                ```

                With body:

                ```
                feat(api): add streaming response support

                Large responses were causing memory issues in production.
                Streaming allows processing chunks incrementally.
                ```

                ## Rules

                - NEVER commit files that may contain secrets
                - NEVER use `git commit --amend` unless the user explicitly requests it
                - NEVER use `--no-verify` to skip hooks
                - If the pre-commit hook fails, fix the issues and create a NEW commit
                - If there are no changes to commit, inform the user and stop
                - Use a HEREDOC to pass the commit message to ensure proper formatting

                ## Execute

                Run the git commands to analyze, stage, and commit the changes now.
              '';
            };
            settings = {
              plugin = [ "opencode-pty" ];
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
              agent = {
                chat = {
                  description = "General purpose chat agent";
                  prompt = "You are a helpful coding assistant. Answer questions, explain code, and help with general programming tasks. Use the available tools to read files, search code, and run commands when needed.";
                };
              };
            };
          };
        };

        systemd.user.services.opencode-web = {
          Unit = {
            After = [ "graphical-session.target" ];
            Wants = [ "graphical-session.target" ];
          };
          Service.Environment = [
            "PATH=/run/wrappers/bin:${config.home.homeDirectory}/.nix-profile/bin:/nix/profile/bin:${config.home.homeDirectory}/.local/state/nix/profile/bin:/etc/profiles/per-user/${config.home.username}/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
            "SUDO_ASKPASS=${pkgs.openssh-askpass}/libexec/gtk-ssh-askpass"
          ];
        };
      };
  };
}
