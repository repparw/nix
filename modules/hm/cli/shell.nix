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
        # timer 12m or t 9m pizza
        set label $argv[2]
        test -z "$label"; and set label "▓▓▓"

        fish -c "sleep $argv[1] && notify-send -i 'task-due' -u critical $label" &> /dev/null
      '';
      # add task to ms to-do
      t = ''
          set nc_user "ubritos@gmail.com"
          set caldav_url "https://leo.it.tab.digital/remote.php/dav/calendars/$nc_user/personal/"
          if not test -f ${osConfig.age.secrets.nextcloud.path}
              echo "Error: pass secret not found" >&2
              exit 1
          end
          set nc_app_pass (cat ${osConfig.age.secrets.nextcloud.path})
            if test (count $argv) -eq 0
                echo "Usage: t TASK DATETIME"
                return 1
            end

            # Get the last argument as the date/time
            set datetime $argv[-1]
            # Get all arguments except the last one as the task summary
            set task_summary (string join " " $argv[1..-2])

            # Convert the date/time string to proper format
            # Check if date is valid first
            if not date -d "$datetime" > /dev/null 2>&1
                # If date parsing fails, use tomorrow 9am as default
                set datetime "tomorrow 9am"
            end

            set is_midnight (date -d "$datetime" +%H%M)
            if test $is_midnight = "0000"
                # If time is midnight (no time specified), make it a day-only task
                set due_time (date -d "$datetime" +%Y%m%dT000000)
                set is_day_only true
            else
                set due_time (date -d "$datetime" +%Y%m%dT%H%M%S)
                set is_day_only false
            end

            # Generate unique identifier
            set UID (uuidgen 2>/dev/null; or date +%s%N)
            set DTSTAMP (date +%Y%m%dT%H%M%S)
            set FILE_NAME "$UID.ics"

            # Construct iCalendar data
            set ICAL_DATA "BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Nextcloud Calendar CLI//NONSGML v1.0//EN
        BEGIN:VTODO
        UID:$UID
        DTSTAMP:$DTSTAMP
        SUMMARY:$task_summary
        DUE;TZID=America/Argentina/Buenos_Aires:$due_time
        PRIORITY:9
        PERCENT-COMPLETE:0
        END:VTODO
        END:VCALENDAR"

            # Display task info with Argentina time
            # Send request to Nextcloud
            set response (curl -s -w "\n%{http_code}" \
                -X PUT \
                --user "$nc_user:$nc_app_pass" \
                -H "Content-Type: text/calendar; charset=utf-8" \
                --data-raw "$ICAL_DATA" \
                "$caldav_url$FILE_NAME")

            set http_code (echo $response | tail -n 1)
            set body (echo $response | head -n -1)

            if test $http_code -eq 201
                if test $is_day_only = true
                    set formatted_time (date -d "$datetime" "+%A %d/%m")
                    notify-send -i 'task-new' "Task created: $task_summary" "Due: $formatted_time (all day)" 2>/dev/null
                else
                    set formatted_time (date -d "$datetime" "+%A %d/%m %H:%M")
                    notify-send -i 'task-new' "Task created: $task_summary" "Due: $formatted_time" 2>/dev/null
                end
            else if test $http_code -ne 201
                echo "Failed to create task (HTTP $http_code)." >&2
                echo "Response Body:" >&2
                echo $body >&2
                echo "iCalendar Data Sent:" >&2
                echo $ICAL_DATA >&2
                notify-send -i 'dialog-error' "Failed to add task: $task_summary" 2>/dev/null
            end
      '';
    };
    # using aliases for defaults, or things that look fugly on expand on abbrs
    shellAliases =
      {
        obsinvim = "cd ~/Documents/obsidian/ && $EDITOR .; prevd";

        # Nix
        vn = "cd ${osConfig.programs.nh.flake}; $EDITOR flake.nix";
        nrs = "nh os switch";
        nup = "cd ${osConfig.programs.nh.flake}; git pull; nix flake update --commit-lock-file; git push; prevd; nrs";
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
        nqterm = "NQDIR=/tmp/nq ${lib.getExe' nq "nqterm"}";
        nqtail = "NQDIR=/tmp/nq ${lib.getExe' nq "nqtail"}";

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
