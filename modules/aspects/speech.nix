{ den, ... }:
{
  den.aspects.speech = {
    includes = [ den.aspects.mpris-playback ];

    homeManager =
      {
        mprisPlayback,
        pkgs,
        ...
      }:
      {
        home.packages = [
          (pkgs.writeShellApplication {
            name = "say";
            runtimeInputs = [
              pkgs.coreutils
              mprisPlayback
              pkgs.pocket-tts
              pkgs.pipewire
            ];
            text = ''
              cleanup() {
                status=$?
                trap - EXIT INT TERM
                mpris-playback resume "$resume_file"
                rm -rf "$temporary_dir"
                exit "$status"
              }

              if [ "$#" -gt 0 ]; then
                text="$*"
              elif [ ! -t 0 ]; then
                text="$(cat)"
              else
                echo "Usage: say <text> (or pipe text on stdin)" >&2
                exit 2
              fi

              if [ -z "$text" ]; then
                echo "say: text must not be empty" >&2
                exit 2
              fi

              temporary_dir="$(mktemp -d)"
              audio="$temporary_dir/speech.wav"
              resume_file="$temporary_dir/paused-players"
              trap cleanup EXIT
              trap 'exit 130' INT
              trap 'exit 143' TERM

              mpris-playback pause "$resume_file"
              pocket-tts generate --quiet --voice eve --text "$text" --output-path "$audio"
              pw-play --volume 0.95 "$audio"
            '';
          })
        ];
      };
  };
}
