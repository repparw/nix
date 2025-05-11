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
        # t 12m or t 9m pizza
        set label $argv[2]
        test -z "$label"; and set label "▓▓▓"

        fish -c "sleep $argv[1] && notify-send -i 'task-due' -u critical $label" &> /dev/null
      '';
      # add task to ms to-do
      t = ''
        if test (count $argv) -eq 0
          echo "Usage: t TASK [time]"
          echo "Time can be:"
          echo "  - morning, evening, tomorrow"
          echo "  - 1h, 12h, 1h30m"
          echo "  - 9 (for 9:00), 21 (for 21:00)"
          echo "  - 24.12. 12:00"
          echo "  - 22.12.2023"
          return 1
        end

        # Check if last argument might be a time specification
        set -l last_arg $argv[-1]
        set -l valid_times morning evening tomorrow

        # Regex patterns for different time formats
        set -l time_delta_pattern '^\d+[dhms](\d+[dhms])*$'        # 1h, 12h30m, etc
        set -l hour_pattern '^([0-9]|1[0-9]|2[0-3])$'             # 9, 21, etc
        set -l date_time_pattern '^\d{1,2}\.\d{1,2}\.\s*\d{1,2}:\d{2}$'  # 24.12. 12:00
        set -l date_pattern '^\d{1,2}\.\d{1,2}\.(\d{2,4})?$'      # 22.12.2023, 01.01.21

        if contains $last_arg $valid_times; or \
           string match -qr $time_delta_pattern $last_arg; or \
           string match -qr $date_time_pattern $last_arg; or \
           string match -qr $date_pattern $last_arg
          # Last word is a valid time format, use it
          set time $last_arg
          set -e argv[-1] # Remove the time from argv
          set task (string join " " $argv)
        else if string match -qr $hour_pattern $last_arg
          # Convert hour-only input to HH:00 format
          set time (printf "%d:00" $last_arg)
          set -e argv[-1]
          set task (string join " " $argv)
        else
          # Last word is not a time, so use default time and all args are task
          set time "morning"
          set task (string join " " $argv)
        end

        todocli new "$task" -r $time
        and notify-send -i 'task-new' "$task @ $time"
      '';
    };
    # using aliases for defaults, or things that look fugly on expand on abbrs
    shellAliases =
      {
        obsinvim = "cd ~/Documents/obsidian/ && $EDITOR .; prevd";

        # Nix
        vn = "cd ~/nix; $EDITOR flake.nix";
        nrs = "nh os switch";
        nup = "cd ~/nix; git pull; nix flake update --commit-lock-file; git push; prevd; nrs";
        nupt = "nh os boot -u";

        x = "xdg-open";
        trash = "mv --force -t ~/.local/share/Trash ";
        ln = "ln -i";
        mv = "mv -i";
        rm = "rm -i";

        chown = "chown --preserve-root";
        chmod = "chmod --preserve-root";
        chgrp = "chgrp --preserve-root";
      }
      // (with pkgs; {
        feh = "${lib.getExe feh} -x -Z -. --image-bg black";

        top = "${lib.getExe bottom} --theme gruvbox";
        diff = "${lib.getExe colordiff}";
        cat = "${lib.getExe bat}";
        df = "${lib.getExe duf} -hide-mp $XDG_CONFIG_HOME\\*";
        du = "${lib.getExe dust}";

        rpi = "${lib.getExe' mosh "mosh"} -P 60001 --ssh 'ssh -p 2222' rpi";
        pc = "${lib.getExe' mosh "mosh"} -P 60000 --ssh 'ssh -p 10000' repparw@repparw.me";

        nq = "NQDIR=/tmp/nq ${lib.getExe' nq "nq"}";
        tq = "NQDIR=/tmp/nq ${lib.getExe' nq "tq"}";
        fq = "NQDIR=/tmp/nq ${lib.getExe' nq "fq"}";

        ns = "${lib.getExe nix-search-tv} print | fzf --preview '${lib.getExe nix-search-tv} preview {}' --scheme history";

        ghcs = "${lib.getExe gh} copilot suggest";
      });
    preferAbbrs = true;
    shellAbbrs = {
      # Asks your passwords, becomes root, opens a interactive non login shell
      su = "sudo -s";

      v = "$EDITOR";

      meminfo = "free -hlt";
      cpuinfo = "lscpu";

      md = "mkdir -pv";
      rd = "rmdir -pv";

      btctl = "bluetoothctl";

      sys = "systemctl";
      sysu = "sys --user";
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
