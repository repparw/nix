{
  pkgs,
  osConfig,
  inputs,
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
      runtimeInputs = [
      ];
      text = ''
        exec uwsm app -- chromium --app="$1" "''${@:2}"
      '';
    })

    (stdenv.mkDerivation {
      pname = "odin4";
      version = "4";

      src = pkgs.fetchzip {
        url = "https://github.com/Adrilaw/OdinV4/releases/download/v1.0/odin.zip";
        hash = "sha256-SoznK53UD/vblqeXBLRlkokaLJwhMZy7wqKufR0I8hI=";
      };

      nativeBuildInputs = [ pkgs.autoPatchelfHook ];

      installPhase = ''
        runHook preInstall
        install -m755 -D odin4 $out/bin/odin4
      '';
    })

    (writeShellApplication {
      name = "bttoggle";
      runtimeInputs = [ bluez ];
      text = ''
        # device=40:5E:F6:CD:0E:F0 # buds
        device=F8:4E:17:E6:22:D2 # xm4

        if bluetoothctl info "$device" | grep -q "Connected: yes"; then
          bluetoothctl disconnect "$device"
        else
          bluetoothctl connect "$device"
        fi
      '';
    })

    (writeShellApplication {
      name = "ndrop";
      runtimeInputs = [
        jq
        libnotify
        niri
        util-linux
        iputils
        coreutils
      ];
      text = builtins.readFile "${inputs.ndrop}/ndrop";
    })

    (writeShellApplication {
      name = "t"; # task quick add for nextcloud caldav
      runtimeInputs = [
        fish
        curl
      ];
      text = ''
        #!/usr/bin/env bash

        # --- Configuration ---
        # User and CalDAV URL for Nextcloud
        nc_user="ubritos@gmail.com"
        caldav_url="https://leo.it.tab.digital/remote.php/dav/calendars/$nc_user/personal/"

        # Path to the secret file containing the Nextcloud app password.
        # This path is expected to be substituted by the Nix build process.
        secret_path="${osConfig.age.secrets.nextcloud.path}"

        # --- Pre-flight Checks ---
        # Check if the secret file exists
        if [[ ! -f "$secret_path" ]]; then
            echo "Error: Nextcloud secret file not found at $secret_path" >&2
            exit 1
        fi

        # Read the app password from the secret file
        nc_app_pass=$(cat "$secret_path")

        # Check if any arguments were provided
        if [ "$#" -eq 0 ]; then
            echo "Usage: t \"TASK SUMMARY\" [DATETIME]"
            echo "Example: t \"Buy milk\" \"tomorrow 9am\""
            exit 1
        fi

        # --- Argument Parsing ---
        # First assume all arguments are part of the task summary
        task_summary="$*"
        datetime="tomorrow 9am"

        # Check if the last argument is a valid date/time
        if date -d "''${!#}" > /dev/null 2>&1; then
            # If it is, use it as datetime and remove it from task summary
            datetime="''${!#}"
            # Get all arguments except the last one as the task summary
            task_summary="''${*:1:$#-1}"
        fi

        # --- Date & Time Processing ---

        # Check if the time is midnight (e.g., no time was specified with the date)
        is_midnight=$(date -d "$datetime" +%H%M)
        if [ "$is_midnight" == "0000" ]; then
            # Format for an all-day event (VEVENT uses DATE, VTODO uses DATETIME)
            due_time=$(date -d "$datetime" +%Y%m%dT000000)
            is_day_only=true
        else
            # Format for a specific time, converting to UTC for the iCalendar standard
            due_time=$(date -u -d "$datetime" +%Y%m%dT%H%M%SZ)
            is_day_only=false
        fi

        # --- iCalendar Data Generation ---
        # Generate a unique identifier for the task. Fallback to timestamp if uuidgen fails.
        TASK_UID=$(uuidgen 2>/dev/null || date +%s%N)
        DTSTAMP=$(date -u +%Y%m%dT%H%M%SZ)
        FILE_NAME="$TASK_UID.ics"

        # Construct the iCalendar (ICS) data payload.
        # Note: For timed events, we use a Z suffix to denote UTC.
        # For all-day events, we specify the timezone in the DUE property.
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
        END:VTODO
        END:VCALENDAR
        EOF
        )

        # --- Send Request to Nextcloud ---
        # Use curl to send the PUT request with the iCalendar data.
        # The -w "%{http_code}" appends the HTTP status code to the output.
        response=$(curl -s -w "\n%{http_code}" \
            -X PUT \
            --user "$nc_user:$nc_app_pass" \
            -H "Content-Type: text/calendar; charset=utf-8" \
            --data-raw "$ICAL_DATA" \
            "$caldav_url$FILE_NAME")

        # Extract the HTTP code and the response body
        http_code=$(echo "$response" | tail -n 1)
        body=$(echo "$response" | sed '$d')

        # --- Handle Response ---
        # Check the HTTP status code to confirm success or failure.
        if [ "$http_code" -eq 201 ]; then
            if [ "$is_day_only" = true ]; then
                formatted_time=$(date -d "$datetime" "+%A %d/%m")
                notify-send -i 'task-new' "Task created: $task_summary" "Due: $formatted_time (all day)" 2>/dev/null
            else
                # Display time in local timezone for the notification
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
      name = "mpvclip";
      runtimeInputs = [
        mpv
      ];
      text = ''
        notify-send -t 2000 'MPV' 'Loading video...'; mpv --no-terminal "$(wl-paste)"
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
}
