{
  pkgs,
  config,
  ...
}:
{
  imports = [
    ./file-manager.nix
    ./rclone.nix
    ./scripts.nix
    ./tmux.nix
    ./shell.nix
  ];

  xdg.enable = true;
  home.preferXdgDirectories = true;

  home.sessionVariables = {
    MANPAGER = "nvim +Man!";
    EDITOR = "nvim";
    VISUAL = "$EDITOR";
  };

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

        # git maintainer standards until git3?
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

        # why not?
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

    opencode = {
      enable = true;
      commands = {
        commit = ''
          # Commit changes
          Stage all changes
          Split staged changes into commits
        '';
      };
      settings = {
        plugin = [
          "opencode-gemini-auth@latest"
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
        agent = {
          chat = {
            description = "General purpose chat agent";
            prompt = "You are a helpful coding assistant. Answer questions, explain code, and help with general programming tasks. Use the available tools to read files, search code, and run commands when needed.";
          };
        };
      };
    };

    ssh = {
      enable = true;
      enableDefaultConfig = false;

      matchBlocks = {
        pi = {
          hostname = "192.168.0.4";
          user = "repparw";
        };
      };
    };

    zoxide = {
      enable = true;
      options = [ "--cmd=cd" ];
    };

  };

  home.packages =
    let
      nvim = pkgs.neovim.extend config.stylix.targets.nixvim.exportedModule;
    in
    with pkgs;
    [
      # essentials
      nvim
      devenv
      curl
      wget
      jq
      libnotify
      nodejs

      android-tools
      unzip
      trashy
      tree
      ffmpeg
      imagemagick
      less
      yt-dlp

      # CLI tools
      playerctl
      libqalculate

      fastfetch
      tlrc # tldr

      pdfgrep
      catdoc # provides catppt and xls2csv

      gemini-cli
      github-copilot-cli

      cfait
    ];
}
