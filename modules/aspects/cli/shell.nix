{
  den,
  pkgs,
  lib,
  ...
}:
{
  den.aspects.shell = {
    includes = [ ];

    nixos = {
      programs.fish.useBabelfish = true;
    };

    homeManager =
      {
        osConfig,
        pkgs,
        lib,
        ...
      }:
      {
        programs = {
          btop.enable = true;

          direnv = {
            enable = true;
            nix-direnv.enable = true;
            silent = true;
          };

          fish = {
            plugins = with pkgs.fishPlugins; [
              {
                name = "pure";
                inherit (pure) src;
              }
              {
                name = "plugin-git";
                inherit (plugin-git) src;
              }
              {
                name = "done";
                inherit (done) src;
              }
            ];
            interactiveShellInit = ''
              if not set -q ZELLIJ; and set -q SSH_TTY
                zellij attach ssh --create
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
            shellAliases = {
              vo = "cd ~/Documents/obsidian/ && $EDITOR .; prevd";

              vn = "cd ${osConfig.programs.nh.flake}; $EDITOR flake.nix";

              nrs = "nh os switch";
              nrb = "nh os boot";
              nrt = "nh os test";

              nrsu = "nrs -u --commit-lock-file";
              nrbu = "nrb -u --commit-lock-file";

              ln = "ln -i";
              mv = "mv -i";

              rg = "rga";
              rt = "trash put";

              chown = "chown --preserve-root";
              chmod = "chmod --preserve-root";
              chgrp = "chgrp --preserve-root";
              top = "btop";
            }
            // (with pkgs; {
              diff = "${lib.getExe colordiff}";
              cat = "${lib.getExe bat}";
              df = "${lib.getExe duf} -hide-mp /home/containers/\\* -only local";
              du = "${lib.getExe dust}";

              rpi = "${lib.getExe' mosh "mosh"} -P 60001 pi";
              pc = "${lib.getExe' mosh "mosh"} -P 60000 alpha";

              ns = "${lib.getExe nix-search-tv} print | fzf --preview '${lib.getExe nix-search-tv} preview {}' --scheme history";
            });
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
  };
}
