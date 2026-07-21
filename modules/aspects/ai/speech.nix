{ den, ... }:
{
  den.aspects.ai.provides.speech.homeManager =
    {
      mprisPlayback,
      pkgs,
      ...
    }:
    let
      detectSpeechLanguage =
        pkgs.writers.writePython3Bin "detect-speech-language"
          {
            libraries = [ pkgs.python3Packages.lexilang ];
          }
          ''
            from sys import argv

            from lexilang.detector import detect


            language, _confidence = detect(argv[1], languages=["en", "es"])
            print({"en": "english", "es": "spanish"}[language])
          '';
    in
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "say";
          runtimeInputs = [
            pkgs.coreutils
            detectSpeechLanguage
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

            language="$(detect-speech-language "$text")"
            pocket-tts generate --quiet --language "$language" --voice eve --text "$text" --output-path "$audio"
            mpris-playback pause "$resume_file"
            pw-play --volume 0.95 "$audio"
          '';
        })
      ];
    };
}
