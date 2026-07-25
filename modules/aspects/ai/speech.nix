{ den, ... }:
{
  den.aspects.ai.provides.speech = {
    nixos =
      { pkgs, ... }:
      {
        services.pipewire.wireplumber.configPackages = [
          (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/50-speech-ducking.conf" ''
            wireplumber.profiles = {
              main = {
                policy.linking.role-based.speech = required
              }
            }

            wireplumber.settings = {
              node.stream.default-media-role = "Multimedia"
              linking.role-based.duck-level = 0.25
            }

            wireplumber.components.rules = [
              {
                matches = [ { provides = "~loopback.sink.role.*" } ]
                actions = {
                  merge = {
                    arguments = {
                      capture.props = {
                        policy.role-based.target = true
                        audio.position = [ FL, FR ]
                        media.class = Audio/Sink
                      }
                      playback.props = {
                        node.passive = true
                        media.role = "Loopback"
                      }
                    }
                    requires = [ support.export-core, pw.node-factory.adapter ]
                  }
                }
              }
            ]

            wireplumber.components = [
              {
                type = virtual
                provides = policy.linking.role-based.speech
                requires = [ loopback.sink.role.multimedia, loopback.sink.role.speech ]
              }
              {
                name = libpipewire-module-loopback
                type = pw-module
                provides = loopback.sink.role.multimedia
                arguments = {
                  node.name = "loopback.sink.role.multimedia"
                  node.description = "Multimedia"
                  capture.props = {
                    device.intended-roles = [ "Music", "Movie", "Game", "Multimedia" ]
                    policy.role-based.priority = 10
                    policy.role-based.action.same-priority = "mix"
                    policy.role-based.action.lower-priority = "mix"
                  }
                }
              }
              {
                name = libpipewire-module-loopback
                type = pw-module
                provides = loopback.sink.role.speech
                arguments = {
                  node.name = "loopback.sink.role.speech"
                  node.description = "Speech"
                  session.suspend-timeout-seconds = 1
                  capture.props = {
                    device.intended-roles = [ "Speech" ]
                    policy.role-based.priority = 20
                    policy.role-based.action.same-priority = "mix"
                    policy.role-based.action.lower-priority = "duck"
                  }
                }
              }
            ]
          '')
        ];
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
