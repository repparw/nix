{
  den,
  ...
}:
{
  den.aspects.git = {
    includes = [ ];

    homeManager =
      { ... }:
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

          codex.enable = true;

          opencode = {
            enable = true;
            commands = {
              commit = ''
                # Commit changes
                Stage all changes
                Split related staged changes into commits
                Ask for confirmation
              '';
            };
            settings = {
              plugin = [
                "opencode-antigravity-auth@latest"
                "@mohak34/opencode-notifier@latest"
              ];
              keybinds = {
                leader = "ctrl+x";
              };
              permission = {
                "*" = {
                  "*" = "allow";
                  "rm *" = "deny";
                };
                "rm *" = "deny";
              };
              formatter = false;
              agent = {
                chat = {
                  description = "General purpose chat agent";
                  prompt = "You are a helpful coding assistant. Answer questions, explain code, and help with general programming tasks. Use the available tools to read files, search code, and run commands when needed.";
                };
              };
            };
          };
        };
      };
  };
}
