{
  den,
  lib,
  ...
}:
{
  den.aspects.phone = {
    nixos = {
      networking.firewall.interfaces.eth0 = {
        allowedTCPPortRanges = [
          {
            from = 1714;
            to = 1764;
          }
        ];
        allowedUDPPortRanges = [
          {
            from = 1714;
            to = 1764;
          }
        ];
      };
    };

    homeManager =
      { pkgs, ... }:
      let
        kdeconnect = pkgs.kdePackages.kdeconnect-kde;
        sendClipboard = pkgs.writeShellApplication {
          name = "kdeconnect-send-clipboard";
          runtimeInputs = with pkgs; [
            coreutils
            gnugrep
            wl-clipboard
          ];
          text = ''
            set -euo pipefail

            device="$(${kdeconnect}/bin/kdeconnect-cli --list-available --id-only | head -n1)"
            if [ -z "$device" ]; then
              ${lib.getExe' pkgs.libnotify "notify-send"} \
                --urgency=critical \
                "KDE Connect" \
                "No paired phone is available"
              exit 1
            fi

            clipboard_types="$(wl-paste --list-types 2>/dev/null || true)"
            uri_mime=""
            if grep -Fqx "text/uri-list" <<< "$clipboard_types"; then
              uri_mime="text/uri-list"
            elif grep -Fqx "x-special/gnome-copied-files" <<< "$clipboard_types"; then
              uri_mime="x-special/gnome-copied-files"
            fi

            if [ -n "$uri_mime" ]; then
              sent=0
              while IFS= read -r uri; do
                uri="''${uri%$'\r'}"
                case "$uri" in
                  "" | \#* | copy | cut)
                    continue
                    ;;
                esac

                ${kdeconnect}/bin/kdeconnect-cli \
                  --device "$device" \
                  --share "$uri"
                sent=1
              done < <(wl-paste --type "$uri_mime")

              if [ "$sent" -eq 1 ]; then
                exit 0
              fi
            fi

            exec ${kdeconnect}/bin/kdeconnect-cli \
              --device "$device" \
              --send-clipboard
          '';
        };
      in
      {
        home.packages = [
          kdeconnect
          sendClipboard
        ];

        systemd.user.services.kdeconnect = {
          Unit = {
            Description = "KDE Connect daemon";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${kdeconnect}/bin/kdeconnectd --replace";
            Restart = "on-failure";
            RestartSec = 3;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };
  };
}
