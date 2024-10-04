{ ... }:
{
  programs.spotify-player = {
    enable = true;
    keymaps = [
      {
        command = "VolumeUp";
        key_sequence = "0";
      }
      {
        command = "VolumeDown";
        key_sequence = "9";
      }
      {
        command = "Mute";
        key_sequence = "m";
      }
      {
        command = "NextTrack";
        key_sequence = "n";
      }
      {
        command = "PreviousTrack";
        key_sequence = "b";
      }
      {
        command = "PreviousTrack";
        key_sequence = "p";
      }
      {
        command = "PreviousPage";
        key_sequence = "q";
      }
      {
        command = "FocusNextWindow";
        key_sequence = "l";
      }
      {
        command = "FocusPreviousWindow";
        key_sequence = "h";
      }
      {
        command = "Quit";
        key_sequence = "C-q";
      }
      {
        command = "LibraryPage";
        key_sequence = "g h";
      }
      {
        command = "LyricPage";
        key_sequence = "g l";
      }
    ];
    actions = [
      {
        action = "CopyLink";
        key_sequence = "y";
        target = "PlayingTrack";
      }
      {
        action = "CopyLink";
        key_sequence = "Y";
      }
      {
        action = "GoToArtist";
        key_sequence = "g A";
        target = "PlayingTrack";
      }
      {
        action = "GoToAlbum";
        key_sequence = "g B";
        target = "PlayingTrack";
      }
      {
        action = "ToggleLiked";
        key_sequence = "C-l";
        target = "PlayingTrack";
      }
    ];
    # uncomment actions and keymaps and rm from dotfiles when merged
    settings = {
      theme = "gruvbox_dark";
      client_id = "2728200c381a418983c3de5b30bc77a9";
      client_port = 8080;
      playback_format = ''
        {track} • {artists}
        {album}
        {metadata}
      '';
      tracks_playback_limit = 50;
      app_refresh_duration_in_ms = 32;
      playback_refresh_duration_in_ms = 0;
      page_size_in_rows = 20;
      play_icon = "▶";
      pause_icon = "▌▌";
      liked_icon = "♥";
      border_type = "Plain";
      progress_bar_type = "Rectangle";
      playback_window_position = "Top";
      cover_img_length = 9;
      cover_img_width = 5;
      cover_img_scale = 1.0;
      playback_window_width = 6;
      enable_streaming = "Always";
      enable_cover_image_cache = true;
      default_device = "spotifyd";
      enable_notify = false;
      copy_command = {
        command = "wl-copy";
        args = [ ];
      };
      device = {
        name = "Terminal UI";
        device_type = "computer";
        volume = 40;
        bitrate = 320;
        audio_cache = false;
        normalization = false;
      };
    };
    themes = [
      {
        name = "gruvbox_dark";
        palette = {
          background = "#282828";
          foreground = "#ebdbb2";
          black = "#282828";
          red = "#cc241d";
          green = "#98971a";
          yellow = "#d79921";
          blue = "#458588";
          magenta = "#b16286";
          cyan = "#689d6a";
          white = "#a89984";
          bright_black = "#928374";
          bright_red = "#fb4934";
          bright_green = "#b8bb26";
          bright_yellow = "#fabd2f";
          bright_blue = "#83a598";
          bright_magenta = "#d3869b";
          bright_cyan = "#8ec07c";
          bright_white = "#ebdbb2";
        };
      }
    ];
  };
}
