{
  den,
  pkgs,
  lib,
  ...
}:
{
  den.aspects.git = {
    includes = [ ];

    homeManager =
      {
        pkgs,
        lib,
        config,
        ...
      }:
      {
        programs = {
          delta = {
            enable = true;
            enableGitIntegration = true;
          };

          eza = {
            enable = true;
            extraOptions = [ "--icons" ];
          };

          fd = {
            enable = true;
            hidden = true;
          };

          fzf = {
            enable = true;
            defaultOptions = [
              "--no-mouse"
              "--multi"
              "--select-1"
              "--reverse"
              "--height 50%"
              "--inline-info"
              "--scheme=history"
            ];
            defaultCommand = "fd --type f --hidden --follow --exclude .git";
          };

          gh = {
            enable = true;
          };

          git = {
            enable = true;

            settings = {
              user = {
                email = "ubritos@gmail.com";
                name = "repparw";
              };
              url = {
                "git@github.com:repparw/" = {
                  insteadOf = "repparw:";
                };
                "git@github.com:" = {
                  insteadOf = "gh:";
                };
              };

              column.ui = "auto";
              branch.sort = "-committerdate";
              tag.sort = "version:refname";
              init.defaultBranch = "main";
              diff = {
                algorithm = "histogram";
                colorMoved = "plain";
                mnemonicPrefix = true;
                renames = true;
              };
              merge = {
                conflictstyle = "zdiff3";
                tool = "nvimdiff";
              };
              mergetool.keepBackup = false;
              push = {
                autoSetupRemote = true;
                followTags = true;
              };
              fetch = {
                prune = true;
                pruneTags = true;
                all = true;
              };

              rerere = {
                enabled = true;
                autoupdate = true;
              };
              pull.rebase = true;
              rebase = {
                autoSquash = true;
                autoStash = true;
                updateRefs = true;
              };
            };
          };

          zoxide = {
            enable = true;
            options = [ "--cmd=cd" ];
          };

          codex = {
            enable = true;
            settings = {
              approval_policy = "on-request";
              sandbox_mode = "workspace-write";
            };

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
              tui.keybinds = {
                leader = "ctrl+x";
              };
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
                    baseURL = "https://opencode.ai/zen/go/v1/chat/completions";
                  };
                  models = {
                    glm-5-1 = {
                      name = "GLM-5.1";
                    };
                    glm-5 = {
                      name = "GLM-5";
                    };
                    kimi-k2-5 = {
                      name = "Kimi K2.5";
                    };
                    kimi-k2-6 = {
                      name = "Kimi K2.6";
                    };
                    mimo-v2-pro = {
                      name = "MiMo-V2-Pro";
                    };
                    mimo-v2-omni = {
                      name = "MiMo-V2-Omni";
                    };
                    mimo-v2-5-pro = {
                      name = "MiMo-V2.5-Pro";
                    };
                    mimo-v2-5 = {
                      name = "MiMo-V2.5";
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

        systemd.user.services.opencode-web.serviceConfig = {
          ExecStart = pkgs.writeShellScript "opencode-web-wrapper" ''
            export PATH="${config.home.profileDirectory}/bin''${PATH:+:$PATH}"
            . "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh"
            exec ${pkgs.opencode}/bin/opencode serve --hostname 0.0.0.0 --port 4096
          '';
          Environment = [
            "SHELL=${lib.getExe pkgs.bash}"
          ];
        };
      };
  };
}
