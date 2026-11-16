{ den, ... }:
{
  den.aspects.ai.provides.dictation = {
    homeManager =
      { pkgs, ... }:
      let
        hexToggle = pkgs.writeShellApplication {
          name = "hex-toggle";
          runtimeInputs = [ pkgs.anomaly-hex ];
          text = ''
            if ! hex status >/dev/null 2>&1; then
              hex start
            fi
            hex dictation toggle
          '';
        };
      in
      {
        home.packages = [
          pkgs.anomaly-hex
          pkgs.wl-clipboard
          pkgs.wtype
          hexToggle

          (pkgs.writeShellApplication {
            name = "translate-selection";
            runtimeInputs = with pkgs; [
              coreutils
              gnused
              libnotify
              translate-shell
              wl-clipboard
              wtype
            ];
            text = ''
              notify() {
                notify-send -t 1500 "Translate selection" "$1"
              }

              trim() {
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
              }

              previous="$(wl-paste --no-newline 2>/dev/null || true)"
              sentinel="translate-selection-no-selection-$$"

              printf '%s' "$sentinel" | wl-copy
              sleep 0.05

              wtype -M ctrl -k c -m ctrl
              sleep 0.15

              selection="$(wl-paste --no-newline 2>/dev/null | trim || true)"

              if [ "$selection" = "$sentinel" ] || [ -z "$selection" ]; then
                wtype -M ctrl -k a -m ctrl
                sleep 0.15
                wtype -M ctrl -k c -m ctrl
                sleep 0.15
                selection="$(wl-paste --no-newline 2>/dev/null | trim || true)"
              fi

              if [ "$selection" = "$sentinel" ] || [ -z "$selection" ]; then
                printf '%s' "$previous" | wl-copy
                notify "No selected text found"
                exit 0
              fi

              english="$(printf '%s' "$selection" | trans -brief :en | trim)"

              if [ -z "$english" ]; then
                notify "English translation failed"
                exit 1
              fi

              if [ "$english" != "$selection" ]; then
                translation="$english"
                direction="Spanish -> English"
              else
                translation="$(printf '%s' "$selection" | trans -brief :es | trim)"
                direction="English -> Spanish"
              fi

              if [ -z "$translation" ]; then
                notify "Spanish translation failed"
                exit 1
              fi

              printf '%s' "$translation" | wl-copy
              sleep 0.05
              wtype -M ctrl -k v -m ctrl
              notify "$direction"
            '';
          })
        ];

      };
  };
}
