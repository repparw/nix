{
  den,
  lib,
  ...
}:
{
  den.aspects.gui.provides.run0 = {
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        # User-level sudo compatibility shim for the Alpha desktop session.
        #
        # It routes only the narrow, safe sudo forms to run0 (polkit) and execs
        # the real setuid sudo for everything else. It never replaces the
        # system sudo: the real binary stays at /run/wrappers/bin/sudo and is
        # reached by absolute path.
        #
        # Supported forms:
        #   sudo -A [--] command [args...]   (askpass form used by agents)
        #   sudo [command [args...]]         (graphical session only)
        #   sudo                             (interactive shell, graphical only)
        #
        # Unsupported options and non-graphical sessions fall back to real sudo.
        shim = pkgs.writeShellScript "sudo-run0-shim" ''
          set -u

          real_sudo=/run/wrappers/bin/sudo
          run0=${pkgs.systemd}/bin/run0

          graphical_session() {
            # SSH sessions keep the real sudo even if they forward DISPLAY.
            if [ -n "''${SSH_CONNECTION:-}" ] || [ -n "''${SSH_CLIENT:-}" ] || [ -n "''${SSH_TTY:-}" ]; then
              return 1
            fi
            [ -n "''${WAYLAND_DISPLAY:-}" ] || [ -n "''${DISPLAY:-}" ]
          }

          # Everything below is scoped to the graphical Alpha session. SSH
          # terminals and other sessions always get the real sudo.
          if graphical_session; then
            # sudo -A [--] command [args...]
            if [ "$#" -gt 0 ] && [ "$1" = "-A" ]; then
              cmd=''${2-}
              if [ "$#" -ge 2 ] && [ "$2" = "--" ]; then
                cmd=''${3-}
              fi
              # If the command itself looks like an option, this is a form we
              # do not translate; let the real sudo handle the original args.
              if [ -n "$cmd" ] && [ "''${cmd#-}" != "''${cmd}" ]; then
                exec "$real_sudo" "$@"
              fi
              shift
              if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then
                shift
              fi
              exec "$run0" "$@"
            fi

            # sudo [command [args...]]
            if [ "$#" -eq 0 ]; then
              exec "$run0"
            fi

            case "$1" in
              -*)
                exec "$real_sudo" "$@"
                ;;
              *)
                exec "$run0" "$@"
                ;;
            esac
          fi

          exec "$real_sudo" "$@"
        '';
      in
      {
        # Prepend the user bin directory so the shim is found before the
        # system sudo. hm-session-vars.sh is sourced by login shells.
        home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

        home.file.".local/bin/sudo".source = shim;

        # Interactive Fish abbreviation, scoped to graphical, non-SSH sessions
        # so SSH terminals keep the real sudo.
        programs.fish.interactiveShellInit = ''
          if not set -q SSH_CONNECTION; and not set -q SSH_CLIENT; and not set -q SSH_TTY
            if set -q WAYLAND_DISPLAY; or set -q DISPLAY
              abbr --add sudo run0
            end
          end
        '';
      };
  };
}
