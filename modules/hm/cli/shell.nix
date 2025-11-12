{
  osConfig,
  pkgs,
  lib,
  ...
}:
{
  programs.fish = {
    enable = true;
    plugins = with pkgs.fishPlugins; [
      {
        name = "pure";
        src = pure.src;
      }
      {
        name = "plugin-git";
        src = plugin-git.src;
      }
      {
        name = "done";
        src = done.src;
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
    functions = {
      fish_mode_prompt = ''''; # hides vi mode indicator
      fish_user_key_bindings = ''
        bind -M insert ctrl-y accept-autosuggestion
        bind -M insert ctrl-e yy
      '';
      timer = ''
        # timer 12m or timer 9m pizza
        set label $argv[2]
        test -z "$label"; and set label "▓▓▓"

        fish -c "sleep $argv[1] && notify-send -i 'task-due' -u critical $label" &> /dev/null
      '';
    };
    # using aliases for defaults, or things that look fugly on expand on abbrs
    shellAliases = {
      obsinvim = "cd ~/Documents/obsidian/ && $EDITOR .; prevd";

      # Nix
      vn = "cd ${osConfig.programs.nh.flake}; $EDITOR flake.nix";
      nrs = "nh os switch";
      nrb = "nh os boot";
      nrsu = "nrs -u";
      nrbu = "nrb -u";

      ln = "ln -i";
      mv = "mv -i";

      rm = "rmtrash -I";
      rmdir = "rmdirtrash";
      rd = "rmdirtrash -pv";

      chown = "chown --preserve-root";
      chmod = "chmod --preserve-root";
      chgrp = "chgrp --preserve-root";
    }
    // (with pkgs; {
      top = "${lib.getExe bottom}";
      diff = "${lib.getExe colordiff}";
      cat = "${lib.getExe bat}";
      df = "${lib.getExe duf} -hide-mp $XDG_CONFIG_HOME\\*";
      du = "${lib.getExe dust}";

      rpi = "${lib.getExe' mosh "mosh"} -P 60001 pi";
      pc = "${lib.getExe' mosh "mosh"} -P 60000 alpha";

      ns = "${lib.getExe nix-search-tv} print | fzf --preview '${lib.getExe nix-search-tv} preview {}' --scheme history";

      ghcs = "${lib.getExe gh} copilot suggest";
    });
    preferAbbrs = true;
    shellAbbrs = {
      # Asks your passwords, becomes root, opens a interactive non login shell
      su = "sudo -s";

      v = "nvim";

      meminfo = "free -hlt";
      cpuinfo = "lscpu";

      md = "mkdir -pv";

      btctl = "bluetoothctl";

      sys = "systemctl";
      sysu = "systemctl --user";
      syslist = "systemctl list-unit-files";

      pcls = "sudo podman container ls";
      pils = "sudo podman image ls";
      prs = "sudo podman restart";
      pxcit = "sudo podman exec -it";
      ppu = "sudo podman pull";
      plo = "sudo podman logs";
      pps = "sudo podman ps";
    };
  };
}
