{
  coreutils,
  playerctl,
  writeShellApplication,
}:
writeShellApplication {
  name = "mpris-playback";
  runtimeInputs = [
    coreutils
    playerctl
  ];
  text = ''
    if [ "$#" -ne 2 ]; then
      echo "Usage: mpris-playback <pause|resume> <state-file>" >&2
      exit 2
    fi

    action="$1"
    state_file="$2"

    case "$action" in
      pause)
        mkdir -p "$(dirname "$state_file")"
        : > "$state_file"

        while IFS= read -r player; do
          [ -n "$player" ] || continue
          if [ "$(playerctl --player "$player" status 2>/dev/null || true)" = "Playing" ]; then
            printf '%s\n' "$player" >> "$state_file"
            playerctl --player "$player" pause 2>/dev/null || true
          fi
        done < <(playerctl -l 2>/dev/null || true)
        ;;
      resume)
        [ -f "$state_file" ] || exit 0

        while IFS= read -r player; do
          [ -n "$player" ] || continue
          playerctl --player "$player" play 2>/dev/null || true
        done < "$state_file"

        rm -f "$state_file"
        ;;
      *)
        echo "mpris-playback: unknown action: $action" >&2
        exit 2
        ;;
    esac
  '';
}
