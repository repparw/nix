{ den, ... }:
{
  den.aspects.speech.homeManager =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "say";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.pocket-tts
            pkgs.pipewire
          ];
          text = ''
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

            audio="$(mktemp --suffix=.wav)"
            trap 'rm -f "$audio"' EXIT

            pocket-tts generate --quiet --voice eve --text "$text" --output-path "$audio"
            pw-play --volume 0.95 "$audio"
          '';
        })
      ];
    };
}
