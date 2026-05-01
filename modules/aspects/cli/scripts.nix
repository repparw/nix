{
  den,
  pkgs,
  ...
}:
{
  den.aspects.scripts = {
    includes = [ ];

    homeManager =
      {
        pkgs,
        osConfig,
        config,
        ...
      }:
      {
        home.packages = with pkgs; [

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

              if todo new --due "$datetime" "$task_summary"; then
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
