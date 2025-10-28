{
  pkgs,
  lib,
  ...
}:
{
  programs.tmux = {
    enable = true;
    shell = "${lib.getExe pkgs.fish}";
    historyLimit = 10000;
    prefix = "C-a";
    mouse = true;
    baseIndex = 1;
    newSession = true;
    keyMode = "vi";
    plugins = with pkgs.tmuxPlugins; [
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
        extraConfig = ''set -g @resurrect-dir "$XDG_DATA_HOME/tmux/resurrect" '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
        '';
      }

      pain-control

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
}
