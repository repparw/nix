{
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.modules.gui.enable {
    programs.spotify-player = {
      enable = true;
      keymaps = [
        {
          command = {
            VolumeChange = {
              offset = 2;
            };
          };
          key_sequence = "0";
        }
        {
          command = {
            VolumeChange = {
              offset = -2;
            };
          };
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
          command = "LyricsPage";
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
      settings = {
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
    };
  };
}
