{
  den,
  ...
}:
{
  den.aspects.gui.provides.spotify = {
    homeManager =
      { ... }:
      {
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
              command = "PreviousTrack";
              key_sequence = "b";
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
            playback_format = ''
              {track} • {artists}
              {album}
              {metadata}
            '';
            cover_img_length = 9;
            enable_streaming = "Never";
            enable_notify = false;
            copy_command = {
              command = "wl-copy";
              args = [ ];
            };
          };
        };
      };
  };
}
