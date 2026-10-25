{
  den,
  pkgs,
  lib,
  ...
}:
{
  den.aspects.fish = {
    includes = [ (den.batteries.user-shell "fish") ];

    nixos = {
      programs.fish = {
        enable = true;
        useBabelfish = true;
      };
    };

    homeManager =
      {
        osConfig,
        pkgs,
        lib,
        config,
        ...
      }:
      {
        programs.fish = {
          plugins = with pkgs.fishPlugins; [
            {
              name = "pure";
              inherit (pure) src;
            }
            {
              name = "done";
              inherit (done) src;
            }
          ];
          interactiveShellInit = ''
            if not set -q TMUX; and set -q SSH_TTY
              tmux new-session -A -s ssh
            end

            set -g fish_key_bindings fish_vi_key_bindings

            if type -q kitty
              alias ssh "kitten ssh"
            end
          '';
          loginShellInit = ''
            set -U fish_greeting
            set -U pure_enable_nixdevshell true
          '';
          binds = {
            "ctrl-y" = {
              mode = "insert";
              command = "accept-autosuggestion";
            };
            "ctrl-e" = {
              mode = "insert";
              command = "y";
            };
            "ctrl-backspace".command = "backward-kill-word";
            "ctrl-backspace-ins" = {
              name = "ctrl-backspace";
              mode = "insert";
              command = "backward-kill-word";
            };
            "yy".command = "fish_clipboard_copy";
          };
          functions = {
            fish_mode_prompt = "";
            timer = ''
              set label $argv[2]
              test -z "$label"; and set label "▓▓▓"

              fish -c "sleep $argv[1] && notify-send -i 'task-due' -u critical $label" &> /dev/null
            '';
          };
          shellAliases = config.home.shellAliases;

          preferAbbrs = true;
          shellAbbrs = {
            su = "sudo -s";

            v = "nvim";

            meminfo = "free -hlt";
            cpuinfo = "lscpu";

            md = "mkdir -pv";

            btctl = "bluetoothctl";

            sys = "systemctl";
            sysu = "systemctl --user";
            syslist = "systemctl list-unit-files";

            cl = "sudo nixos-container list";
            crs = "sudo nixos-container restart";
            csh = "sudo nixos-container root-login";
            crun = "sudo nixos-container run";
            clo = "journalctl -xeu 'container@*'";
            cps = "systemctl list-units 'container@*'";
            cst = "sudo systemctl start container@";
            csp = "sudo systemctl stop container@";
          };
        };
      };
  };
}
