{
  den,
  pkgs,
  ...
}:
{
  den.aspects.scripts = {
    includes = [ ];

    homeManager =
      { pkgs, osConfig, ... }:
      {
        home.packages = with pkgs; [
          (writeShellApplication {
            name = "media-play-pause";
            runtimeInputs = [ playerctl ];
            text = ''
              if [ "$(playerctl status)" = "Playing" ]; then
                playerctl -a pause
              else
                playerctl --player=spotifyd play
              fi
            '';
          })

          (writeShellApplication {
            name = "clip2text";
            runtimeInputs = [
              wl-clipboard
              tesseract
            ];
            text = ''
              wl-paste | tesseract - stdout | wl-copy
            '';
          })

          (writeShellApplication {
            name = "clip2qr";
            runtimeInputs = [
              wl-clipboard
              zbar
            ];
            text = ''
              wl-paste --type image/png | zbarimg --raw - | wl-copy
            '';
          })

          (writeShellApplication {
            name = "webapp";
            text = ''
              exec chromium --app="$1" "''${@:2}"
            '';
          })

          (writeShellApplication {
            name = "bttoggle";
            runtimeInputs = [ bluez ];
            text = ''
              device=F8:4E:17:E6:22:D2 # xm4

              if bluetoothctl info "$device" | grep -q "Connected: yes"; then
                bluetoothctl disconnect "$device"
              else
                bluetoothctl connect "$device"
              fi
            '';
          })

          (writeShellApplication {
            name = "mpvclip";
            runtimeInputs = [
              libnotify
              mpv
              wl-clipboard
            ];
            text = ''
              notify-send -t 2000 'MPV' 'Loading video...'; mpv --no-terminal "$(wl-paste)"
            '';
          })

          (writeShellApplication {
            name = "hotswap";
            text = ''
              if [ $# -eq 0 ]; then
                echo "Usage: hotswap <file>"
                exit 1
              fi

              file="$1"

              if [ ! -e "$file" ]; then
                echo "Error: File '$file' does not exist"
                exit 1
              fi

              if [ ! -L "$file" ]; then
                echo "File is not a symlink, nothing to do"
                exit 1
              fi

              target="$(readlink -f "$file")"
              temp="$(mktemp)"

              cp "$target" "$temp"

              if nvim "$temp"; then
                rm "$file"
                mv "$temp" "$file"
                echo "Saved."
              else
                rm "$temp"
                echo "Edit canceled."
              fi
            '';
          })

          (writeShellApplication {
            name = "t";
            runtimeInputs = [
              curl
              libnotify
              util-linux
            ];
            text = ''
              nc_user="ubritos@gmail.com"
              caldav_url="https://leo.it.tab.digital/remote.php/dav/calendars/$nc_user/personal/"
              secret_path="${osConfig.sops.secrets.nextcloud.path}"

              if [[ ! -f "$secret_path" ]]; then
                  echo "Error: Nextcloud secret file not found at $secret_path" >&2
                  exit 1
              fi

              nc_app_pass=$(cat "$secret_path")

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
                  due_time=$(date -d "$datetime" +%Y%m%dT000000)
                  is_day_only=true
              else
                  due_time=$(date -u -d "$datetime" +%Y%m%dT%H%M%SZ)
                  is_day_only=false
              fi

              TASK_UID=$(uuidgen 2>/dev/null || date +%s%N)
              DTSTAMP=$(date -u +%Y%m%dT%H%M%SZ)
              FILE_NAME="$TASK_UID.ics"

              if [ "$is_day_only" = true ]; then
                  DUE_LINE="DUE;VALUE=DATE:$(date -d "$datetime" +%Y%m%d)"
              else
                  DUE_LINE="DUE:$due_time"
              fi

              ICAL_DATA=$(cat <<EOF
              BEGIN:VCALENDAR
              VERSION:2.0
              PRODID:-//Bash Script//NONSGML v1.0//EN
              BEGIN:VTODO
              UID:$TASK_UID
              DTSTAMP:$DTSTAMP
              SUMMARY:$task_summary
              $DUE_LINE
              PRIORITY:9
              PERCENT-COMPLETE:0
              BEGIN:VALARM
              ACTION:DISPLAY
              TRIGGER;VALUE=DATE-TIME:$due_time
              DESCRIPTION:$task_summary
              END:VALARM
              END:VTODO
              END:VCALENDAR
              EOF
              )

              response=$(curl -s -w "\n%{http_code}" \
                  -X PUT \
                  --user "$nc_user:$nc_app_pass" \
                  -H "Content-Type: text/calendar; charset=utf-8" \
                  --data-raw "$ICAL_DATA" \
                  "$caldav_url$FILE_NAME")

              http_code=$(echo "$response" | tail -n 1)
              body=$(echo "$response" | sed '$d')

              if [ "$http_code" -eq 201 ]; then
                  if [ "$is_day_only" = true ]; then
                      formatted_time=$(date -d "$datetime" "+%A %d/%m")
                      notify-send -i 'task-new' "Task created: $task_summary" "Due: $formatted_time (all day)" 2>/dev/null
                  else
                      formatted_time=$(date -d "$datetime" "+%A %d/%m %H:%M")
                      notify-send -i 'task-new' "Task created: $task_summary" "Due: $formatted_time" 2>/dev/null
                  fi
              else
                  echo "Error: Failed to create task (HTTP status: $http_code)." >&2
                  echo "Response Body: $body" >&2
                  echo "--------------------" >&2
                  echo "iCalendar Data Sent:" >&2
                  echo "$ICAL_DATA" >&2
                  notify-send -i 'dialog-error' "Failed to add task: $task_summary" "HTTP: $http_code" 2>/dev/null
              fi
            '';
          })

          (writeShellApplication {
            name = "obs-remux2wsp";
            runtimeInputs = [ ffmpeg ];
            text = ''
              cd /mnt/hdd/Videos/obs;
              FILE=$(find '.' ./*.mkv -maxdepth 0 -type f -printf '%T@ %p
              ' | sort -k 1nr | sed 's/^[^ ]* //' | head -n 1
              )
              ffmpeg -sseof -60 -i "$FILE" -vcodec libx264 -ac 1 -acodec copy -pix_fmt yuv420p "''${FILE%.*}".mp4;
            '';
          })
        ];
      };
  };
}
