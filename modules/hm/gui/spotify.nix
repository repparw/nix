{
  lib,
  osConfig,
  ...
}:
{
  config = lib.mkIf osConfig.modules.gui.enable {
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
        enable_streaming = "DaemonOnly";
        enable_cover_image_cache = true;
        default_device = osConfig.networking.hostName;
        enable_notify = false;
        copy_command = {
          command = "wl-copy";
          args = [ ];
        };
      };
    };
    services.spotifyd = {
      settings = {
        global = {
          username = "2ksy00sfypgevoabx2128ia4g";
          use_mpris = true;

          dbus_type = "session";
          backend = "pulseaudio";
          audio_format = "S24";

          device_name = osConfig.networking.hostName;

          bitrate = 320;

          cache_path = "/home/repparw/.cache/spotifyd";

          max_cache_size = 5000000000;

          initial_volume = 45;

          volume_normalisation = false;

          device_type = "speaker";
        };
      };
    };
  };
}
