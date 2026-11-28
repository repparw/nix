{
  den,
  ...
}:
{
  den.aspects.gui.provides.todo = {
    homeManager =
      {
        lib,
        osConfig,
        pkgs,
        ...
      }:
      let
        caldavList = "https://leo.it.tab.digital/remote.php/dav/calendars/ubritos%40gmail.com/personal";
        # Reuse the Nextcloud app password provisioned by ../cli/rclone.nix.
        passwordFile = osConfig.sops.secrets.rcloneNextcloud.path;

        todoExtension = pkgs.runCommandLocal "todo" { } ''
          mkdir -p "$out"
          cp ${
            pkgs.writeText "vicinae-todo-package.json" (
              builtins.toJSON {
                "$schema" =
                  "https://raw.githubusercontent.com/vicinaehq/vicinae/refs/heads/main/extra/schemas/extension.json";
                name = "todo";
                title = "Todo";
                description = "Create tasks in the personal Nextcloud list";
                categories = [ "Productivity" ];
                license = "MIT";
                author = "repparw";
                # Vicinae supplies this API at runtime.
                dependencies."@vicinae/api" = "0.16.8";
                commands = [
                  {
                    name = "add";
                    title = "Add Todo";
                    description = "Create a todo item";
                    mode = "no-view";
                    arguments = [
                      {
                        name = "task";
                        placeholder = "Task";
                        type = "text";
                        required = true;
                      }
                      {
                        name = "due";
                        placeholder = "Due, e.g. tomorrow 9am";
                        type = "text";
                        required = false;
                      }
                    ];
                  }
                ];
              }
            )
          } "$out/package.json"
          cp ${pkgs.writeText "vicinae-todo-add.js" ''
            "use strict";

            const { showHUD, showToast, Toast } = require("@vicinae/api");
            const { closeMainWindow } = require("@raycast/api");
            const { execFile } = require("node:child_process");
            const { promisify } = require("node:util");

            const execFileAsync = promisify(execFile);
            const todo = "${lib.getExe t}";

            function getArguments(props) {
              const args = props?.arguments ?? {};
              return {
                task: String(args.task ?? "").trim(),
                due: String(args.due ?? "").trim(),
              };
            }

            async function main(props) {
              const { task, due } = getArguments(props);

              if (!task) {
                await showToast({
                  style: Toast.Style.Failure,
                  title: "Task required",
                  message: "Enter a task to create.",
                });
                return;
              }

              const toast = await showToast({
                style: Toast.Style.Animated,
                title: "Creating task...",
              });
              try {
                await execFileAsync(todo, due ? [task, due] : [task], { timeout: 35_000 });
              } catch (error) {
                const message =
                  error?.stderr?.trim() ||
                  error?.stdout?.trim() ||
                  error?.message ||
                  String(error);

                toast.title = "Failed to create task";
                toast.message = message;
                toast.style = Toast.Style.Failure;
                return;
              }

              if (typeof showHUD === "function") {
                await toast.hide();
                await showHUD("Task created");
              } else {
                toast.title = "Task created";
                toast.message = due ? task + " - " + due : task;
                toast.style = Toast.Style.Success;
                await new Promise((resolve) => setTimeout(resolve, 1500));
                await closeMainWindow();
              }
            }

            module.exports = { default: main };
          ''} "$out/add.js"
        '';

        t = pkgs.writeShellApplication {
          name = "t";
          runtimeInputs = with pkgs; [
            coreutils
            curl
            util-linux
          ];
          text = ''
            trim() {
                local value="$1"
                value="''${value#"''${value%%[![:space:]]*}"}"
                printf '%s' "''${value%"''${value##*[![:space:]]}"}"
            }

            task_summary=$(trim "''${1-}")
            if [[ $# -lt 1 || $# -gt 2 || -z "$task_summary" ]]; then
                echo 'Usage: t "TASK SUMMARY" [DATETIME]' >&2
                exit 1
            fi

            datetime=$(trim "''${2-}")
            due_line=""
            timed_due=false
            if [[ -n "$datetime" ]]; then
                # GNU date accepts relative offsets without the leading "in".
                date_input="''${datetime,,}"
                if [[ "$date_input" =~ ^in[[:space:]]+ ]]; then
                    date_input="''${date_input#"''${BASH_REMATCH[0]}"}"
                fi
                if [[ "$date_input" =~ (^|[[:space:]])(noon|midnight)($|[[:space:]]) ]]; then
                    clock=12:00
                    if [[ "''${BASH_REMATCH[2]}" == midnight ]]; then
                        clock=00:00
                    fi
                    date_input="''${date_input/"''${BASH_REMATCH[0]}"/"''${BASH_REMATCH[1]}$clock''${BASH_REMATCH[3]}"}"
                fi
                if ! due_epoch=$(date -d "$date_input" +%s 2>/dev/null); then
                    echo "Error: Invalid due date: $datetime" >&2
                    exit 1
                fi

                time_pattern='[0-9]:[0-9]|[0-9]t[0-9]|^@|(^|[^[:alpha:]])([ap]\.?m\.?|hours?|mins?|minutes?|secs?|seconds?)($|[^[:alpha:]])'
                if [[ "$date_input" =~ $time_pattern ]]; then
                    timed_due=true
                    due_line="DUE:$(date -u -d "@$due_epoch" +%Y%m%dT%H%M%SZ)"
                else
                    due_line="DUE;VALUE=DATE:$(date -d "@$due_epoch" +%Y%m%d)"
                fi
            fi

            if [[ ! -r "${passwordFile}" ]]; then
                echo "Error: Nextcloud secret file is unreadable at ${passwordFile}" >&2
                exit 1
            fi
            # Accept a secret with or without a final newline.
            IFS= read -r nc_app_pass < "${passwordFile}" || true
            nc_app_pass="''${nc_app_pass%$'\r'}"
            if [[ -z "$nc_app_pass" ]]; then
                echo "Error: Nextcloud secret file is empty at ${passwordFile}" >&2
                exit 1
            fi

            escape_ical_text() {
                local value="$1"
                value="''${value//\\/\\\\}"
                value="''${value//;/\\;}"
                value="''${value//,/\\,}"
                value="''${value//$'\r\n'/\\n}"
                value="''${value//$'\r'/\\n}"
                value="''${value//$'\n'/\\n}"
                printf '%s' "$value"
            }

            escape_curl_config() {
                local value="$1"
                value="''${value//\\/\\\\}"
                value="''${value//\"/\\\"}"
                printf '%s' "$value"
            }

            # RFC 5545 lines have a 75-octet folding limit, including UTF-8.
            fold_ical_line() {
                local LC_ALL=C.UTF-8
                local line="$1" width=0 ch size i
                for ((i = 0; i < ''${#line}; i++)); do
                    ch="''${line:i:1}"
                    LC_ALL=C
                    size=''${#ch}
                    LC_ALL=C.UTF-8
                    if ((width + size > 75)); then
                        printf '\r\n '
                        width=1
                    fi
                    printf '%s' "$ch"
                    width=$((width + size))
                done
                printf '\r\n'
            }

            task_text=$(escape_ical_text "$task_summary")
            task_uid=$(uuidgen)
            dtstamp=$(date -u +%Y%m%dT%H%M%SZ)
            curl_user=$(escape_curl_config "ubritos@gmail.com:$nc_app_pass")

            ical_lines=(
                "BEGIN:VCALENDAR"
                "VERSION:2.0"
                "PRODID:-//repparw t//EN"
                "BEGIN:VTODO"
                "UID:$task_uid"
                "DTSTAMP:$dtstamp"
                "CREATED:$dtstamp"
                "STATUS:NEEDS-ACTION"
                "PERCENT-COMPLETE:0"
                "SUMMARY:$task_text"
            )
            if [[ -n "$due_line" ]]; then
                ical_lines+=("$due_line")
            fi
            if [[ "$timed_due" == true ]]; then
                ical_lines+=(
                    "BEGIN:VALARM"
                    "ACTION:DISPLAY"
                    "TRIGGER;RELATED=END:PT0S"
                    "DESCRIPTION:$task_text"
                    "END:VALARM"
                )
            fi
            ical_lines+=(
                "END:VTODO"
                "END:VCALENDAR"
            )

            response_file=$(mktemp)
            trap 'rm -f -- "$response_file"' EXIT
            if ! http_code=$(
                for line in "''${ical_lines[@]}"; do
                    fold_ical_line "$line"
                done |
                    curl -sS -o "$response_file" -w '%{http_code}' \
                        --connect-timeout 10 --max-time 30 \
                        --config <(printf 'user = "%s"\n' "$curl_user") \
                        -X PUT \
                        -H 'If-None-Match: *' \
                        -H 'Content-Type: text/calendar; charset=utf-8' \
                        --data-binary @- \
                        "${caldavList}/$task_uid.ics"
            ); then
                echo "Error: Failed to contact Nextcloud CalDAV" >&2
                exit 1
            fi

            if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
                echo "Task created: $task_summary"
            else
                echo "Error: Failed to create task (HTTP status: $http_code)." >&2
                response=$(head -c 512 "$response_file" | tr '\r\n\t' ' ' | LC_ALL=C tr -d '[:cntrl:]')
                response=$(trim "$response")
                if [[ -n "$response" ]]; then
                    printf '%s\n' "$response" >&2
                fi
                exit 1
            fi
          '';
        };
      in
      {
        home.packages = [ t ];

        programs.vicinae.extensions = [ todoExtension ];
      };
  };
}
