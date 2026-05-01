{ den, ... }:
{
  den.aspects.tasks = {
    includes = [ ];

    homeManager =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          (writeShellApplication {
            name = "t";
            runtimeInputs = [
              libnotify
              todoman
            ];
            text = ''
              if [ "$#" -eq 0 ]; then
                  echo "Usage: t \"TASK SUMMARY\" [DATETIME]"
                  echo "Example: t \"Buy milk\" \"tomorrow 9am\""
                  exit 1
              fi

              task_summary="$*"
              datetime="tomorrow 9am"

              if date -d "''${!#}" > /dev/null 2>&1; then
                  datetime="''${!#}"
                  task_summary="''${*:1:$#-1}"
              fi

              is_midnight=$(date -d "$datetime" +%H%M)
              if [ "$is_midnight" == "0000" ]; then
                  is_day_only=true
              else
                  is_day_only=false
              fi

              if todo new --priority low --due "$datetime" "$task_summary"; then
                  if [ "$is_day_only" = true ]; then
                      formatted_time=$(date -d "$datetime" "+%A %d/%m")
                      notify-send -i 'task-new' "Task created: $task_summary" "Due: $formatted_time (all day)" 2>/dev/null
                  else
                      formatted_time=$(date -d "$datetime" "+%A %d/%m %H:%M")
                      notify-send -i 'task-new' "Task created: $task_summary" "Due: $formatted_time" 2>/dev/null
                  fi
              else
                  notify-send -i 'dialog-error' "Failed to add task: $task_summary" 2>/dev/null
              fi
            '';
          })
        ];

        accounts.calendar = {
          basePath = ".local/share/calendars";
          accounts.nextcloud = {
            remote = {
              type = "caldav";
              url = "https://leo.it.tab.digital/remote.php/dav/calendars/ubritos@gmail.com/";
              userName = "ubritos@gmail.com";
              passwordCommand = [
                "cat"
                "/run/secrets/nextcloud"
              ];
            };
            vdirsyncer = {
              enable = true;
              collections = [ "from a" ];
            };
          };
        };

        programs.vdirsyncer.enable = true;

        services.vdirsyncer = {
          enable = true;
          frequency = "*:0/5";
        };

        programs.todoman = {
          enable = true;
          glob = "*/*";
          extraConfig = ''
            default_list = "Personal"
            default_command = "list --due 48"
          '';
        };
      };
  };
}
