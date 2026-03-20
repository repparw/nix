{
  den,
  pkgs,
  config,
  ...
}:
{
  den.aspects.editors = {
    includes = [ ];

    homeManager =
      {
        pkgs,
        config,
        ...
      }:
      {
        home.sessionVariables = {
          MANPAGER = "nvim +Man!";
          EDITOR = "nvim";
          VISUAL = "$EDITOR";
        };

        programs = {
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
              formatter = false;
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
        };

        home.packages =
          let
            nvim = pkgs.neovim.extend config.stylix.targets.nixvim.exportedModule;
          in
          with pkgs;
          [
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

            playerctl
            libqalculate

            fastfetch
            tlrc

            pdfgrep
            catdoc

            gemini-cli
            github-copilot-cli

            cfait
          ];
      };
  };
}
