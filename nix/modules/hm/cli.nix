{ pkgs, unstable, ... }:

{
  programs = {
    git = {
      enable = true;
      userEmail = "ubritos@gmail.com";
      userName = "repparw";
      extraConfig = {
        rerere.enabled = true;
        pull.rebase = true;
      };
    };
  };

  programs.tmux = {
    enable = true;
    shell = "${pkgs.zsh}/bin/zsh";
    terminal = "xterm-kitty";
    historyLimit = 10000;
    prefix = "C-a";
    mouse = true;
    baseIndex = 1;
    newSession = true;
    keyMode = "vi";
    plugins = with unstable.tmuxPlugins; [
      {
        plugin = power-theme;
        extraConfig = ''
          set -g @tmux_power_theme 'everforest'
          set -g @tmux_power_date_format '%F'
          set -g @tmux_power_time_format '%H:%M'
          set -g @tmux_power_date_icon ' '
          set -g @tmux_power_time_icon ' '
          set -g @tmux_power_user_icon ' '
          set -g @tmux_power_session_icon ' '
          set -g @tmux_power_right_arrow_icon     ''
          set -g @tmux_power_left_arrow_icon      ''
        '';
      }
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-dir "$XDG_DATA_HOME/tmux/resurrect"
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
        '';
      }

      pain-control
      #power-zoom
      #tmux-floax TODO
      vim-tmux-navigator
      yank
    ];
    extraConfig = ''
      bind-key @ command-prompt -p "create pane from:" "join-pane -s ':%%'"

      # Shift Alt vim keys to switch windows
      bind -n M-H previous-window
      bind -n M-L next-window

      set-option -g update-environment "DISPLAY WAYLAND_DISPLAY SSH_AUTH_SOCK"

      # keybindings
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel

      bind '"' split-window -v -c "#{pane_current_path}"
      bind % split-window -h -c "#{pane_current_path}"

      bind C-l send-keys 'C-l'
    '';
  };

  programs.ssh.addKeysToAgent = "yes";

  home.packages =
    with pkgs;
    [
      # essentials
      zsh
      curl
      wget
      unzip
      bluez
      jq
      tree
      ffmpeg
      imagemagick
      less
      base16-schemes
      yt-dlp
      fzf
      ytfzf

      # CLI tools
      playerctl
      rclone
      melt # ssh ed25519 keys to seed words
      ueberzugpp
      libqalculate

      fastfetch
      axel
      tlrc # tldr
      nq # Command queue

      lf
      vimv-rs # bulk rename
      pdfgrep
      catdoc # provides catppt and xls2csv

      tig

      # Modern replacements of basic tools
      unstable.bottom
      bat
      colordiff
      duf
      du-dust
      fd
      ripgrep
      zoxide
      eza
      tree

      manix

      nodejs # remove after porting nvim plugins to nix cfg
    ]
    ++ (with unstable; [
      nvim-pkg
    ]);
}
