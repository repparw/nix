{
  pkgs,
  lib,
  ...
}: {
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

      function t # t 12m or t 9m pizza
        set label $argv[2]
        test -z "$label"; and set label "▓▓▓"

        fish -c "sleep $argv[1] && notify-send -u critical -t 0 $label" &> /dev/null
      end

      if type -q kitty
        alias ssh "kitten ssh"
      end
    '';
    loginShellInit = ''
      set -U fish_greeting
      function fish_mode_prompt; end # hides vi mode

      set -U pure_enable_nixdevshell true
    '';
    shellInit = ''
      function fish_user_key_bindings
        bind -M insert ctrl-y accept-autosuggestion
        bind -M insert ctrl-e yazi
      end
    '';
  };
  home = {
    shellAliases =
      {
        sudo = "sudo ";

        # Asks your passwords, becomes root, opens a interactive non login shell
        su = "sudo -s";

        v = "$EDITOR";

        obsinvim = "cd ~/Documents/obsidian/ && $EDITOR .; 1";

        # Nix
        vn = "cd ~/nix; $EDITOR flake.nix";

        nrs = "nh os switch";
        nup = "nh os switch -u";
        nupt = "nh os boot -u";

        x = "xdg-open";
        trash = "mv --force -t ~/.local/share/Trash ";

        ln = "ln -i";
        mv = "mv -i";
        rm = "rm -i";

        chown = "chown --preserve-root";
        chmod = "chmod --preserve-root";
        chgrp = "chgrp --preserve-root";

        mnt = "mount | awk -F' ' '{ printf \"%s\t%s\n\",\$1,\$3; }' | column -t | egrep ^/dev/ | sort";

        ping = "ping -c 5";

        meminfo = "free -h -l -t";
        cpuinfo = "lscpu";

        mkdir = "mkdir -pv";

        btctl = "bluetoothctl";

        sys = "systemctl";
        sysu = "sys --user";
        syslist = "systemctl list-unit-files";

        yd = "yt-dlp";

        pcls = "podman container ls";
        pils = "podman image ls";
        prs = "podman restart";
        pxcit = "podman exec -it";
        ppu = "podman pull";
        pps = "podman ps";
      }
      // (with pkgs; {
        feh = "${lib.getExe feh} -x -Z -. --image-bg black";

        top = "${lib.getExe bottom} --theme gruvbox";
        diff = "${lib.getExe colordiff}";
        cat = "${lib.getExe bat}";
        df = "${lib.getExe duf}";
        du = "${lib.getExe dust}";

        rpi = "${lib.getExe' mosh "mosh"} -P 60001 --ssh 'ssh -p 2222' rpi";
        pc = "${lib.getExe' mosh "mosh"} -P 60000 --ssh 'ssh -p 10000' repparw@repparw.me";

        nq = "NQDIR=/tmp/nq ${lib.getExe' nq "nq"}";
        tq = "NQDIR=/tmp/nq ${lib.getExe' nq "tq"}";
        fq = "NQDIR=/tmp/nq ${lib.getExe' nq "fq"}";

        ns = "${lib.getExe nix-search-tv} print | fzf --preview '${lib.getExe nix-search-tv} preview {}' --scheme history";

        ghcs = "${lib.getExe gh} copilot suggest";
      });
  };
}
