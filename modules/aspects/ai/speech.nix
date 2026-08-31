{ den, ... }:
{
  den.aspects.ai.provides.speech = {
    nixos = {
      services.pipewire = {
        extraConfig.pipewire."50-speech-loopback" = {
          "context.modules" = [
            {
              name = "libpipewire-module-loopback";
              args = {
                "node.name" = "loopback.sink.role.multimedia";
                "node.description" = "Multimedia";
                "capture.props" = {
                  "node.name" = "loopback.sink.role.multimedia";
                  "media.class" = "Audio/Sink";
                  "audio.position" = [
                    "FL"
                    "FR"
                  ];
                  "device.intended-roles" = [
                    "Music"
                    "Movie"
                    "Game"
                    "Multimedia"
                  ];
                  "policy.role-based.target" = true;
                  "policy.role-based.priority" = 10;
                  "policy.role-based.action.same-priority" = "mix";
                  "policy.role-based.action.lower-priority" = "mix";
                };
                "playback.props" = {
                  "node.name" = "loopback.src.role.multimedia";
                  "media.role" = "Loopback";
                  "node.passive" = true;
                };
              };
            }
            {
              name = "libpipewire-module-loopback";
              args = {
                "node.name" = "loopback.sink.role.speech";
                "node.description" = "Speech";
                "capture.props" = {
                  "node.name" = "loopback.sink.role.speech";
                  "media.class" = "Audio/Sink";
                  "audio.position" = [
                    "FL"
                    "FR"
                  ];
                  "device.intended-roles" = [ "Speech" ];
                  "policy.role-based.target" = true;
                  "policy.role-based.priority" = 20;
                  "policy.role-based.action.same-priority" = "mix";
                  "policy.role-based.action.lower-priority" = "duck";
                  # Shorten the loopback's idle-to-suspend delay. Zero disables
                  # suspension, so it would keep the role links around.
                  "session.suspend-timeout-seconds" = 0.25;
                };
                "playback.props" = {
                  "node.name" = "loopback.src.role.speech";
                  "media.role" = "Loopback";
                  "node.passive" = true;
                };
              };
            }
          ];
        };

        wireplumber.extraConfig."99-speech-ducking" = {
          "wireplumber.settings" = {
            "node.stream.default-media-role" = "Multimedia";
            "linking.role-based.duck-level" = 0.25;
            "node.restore-default-targets" = false;
          };
          "node.rules" = [
            {
              matches = [
                {
                  "application.name" = "ZapZap";
                  "media.class" = "Audio/Source";
                }
              ];
              actions = {
                "update-props" = {
                  "media.role" = "Speech";
                  "node.pause-on-idle" = false;
                };
              };
            }
          ];
        };

        extraConfig.pipewire-pulse."99-zapzap-media-role" = {
          # ZapZap is a QtWebEngine wrapper, so tagging the process with
          # PULSE_PROP_media.role also tags its notification sounds. Let the
          # browser classify media streams and only promote actual music/video
          # streams to Speech; Notification streams stay out of ducking.
          "stream.rules" = [
            {
              matches = [
                {
                  "application.name" = "ZapZap";
                  "media.role" = "Movie";
                }
                {
                  "application.name" = "ZapZap";
                  "media.role" = "Music";
                }
                {
                  "application.name" = "ZapZap";
                  "media.role" = "video";
                }
                {
                  "application.name" = "ZapZap";
                  "media.role" = "music";
                }
                {
                  "application.name" = "ZapZap";
                  "media.class" = "Audio/Source";
                }
              ];
              actions = {
                "update-props" = {
                  "media.role" = "Speech";
                };
              };
            }
          ];
        };
      };
    };

    homeManager =
      {
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
              pkgs.pocket-tts
              pkgs.pipewire
            ];
            text = ''
              cleanup() {
                status=$?
                trap - EXIT INT TERM
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
              trap cleanup EXIT
              trap 'exit 130' INT
              trap 'exit 143' TERM

              language="$(detect-speech-language "$text")"
              pocket-tts generate --quiet --language "$language" --voice eve --text "$text" --output-path "$audio"
              pw-play --media-role Speech --volume 0.95 "$audio"
            '';
          })
        ];
      };
  };
}
