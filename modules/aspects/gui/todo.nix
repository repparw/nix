{
  den,
  ...
}:
{
  den.aspects.gui.provides.todo = {
    homeManager =
      {
        config,
        osConfig,
        pkgs,
        ...
      }:
      let
        caldavList = "https://leo.it.tab.digital/remote.php/dav/calendars/ubritos%40gmail.com/personal";
        passwordFile = osConfig.sops.secrets.rcloneNextcloud.path;

        todoExtension = pkgs.runCommandLocal "vicinae-todo-extension" { } ''
          mkdir -p "$out"
          cp ${
            pkgs.writeText "vicinae-todo-package.json" (
              builtins.toJSON {
                "$schema" =
                  "https://raw.githubusercontent.com/vicinaehq/vicinae/refs/heads/main/extra/schemas/extension.json";
                name = "todo";
                title = "Todo";
                description = "Create tasks in the Nextcloud lists used by tasks-org";
                categories = [ "Productivity" ];
                license = "MIT";
                author = "repparw";
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

            const { closeMainWindow, showToast, Toast } = require("@vicinae/api");
            const { execFile } = require("node:child_process");
            const { promisify } = require("node:util");

            const execFileAsync = promisify(execFile);
            const todo = "${config.home.profileDirectory}/bin/t";

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

              try {
                await execFileAsync(todo, due ? [task, due] : [task]);
                await showToast({
                  style: Toast.Style.Success,
                  title: "Task created",
                  message: due ? task + " - " + due : task,
                });
                await closeMainWindow();
              } catch (error) {
                const message =
                  error?.stderr?.trim() ||
                  error?.stdout?.trim() ||
                  error?.message ||
                  String(error);

                await showToast({
                  style: Toast.Style.Failure,
                  title: "Failed to create task",
                  message,
                });
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
            if [[ $# -lt 1 || $# -gt 2 || -z "$1" ]]; then
                echo 'Usage: t "TASK SUMMARY" [DATETIME]' >&2
                exit 1
            fi

            if [[ ! -f "${passwordFile}" ]]; then
                echo "Error: Nextcloud secret file not found at ${passwordFile}" >&2
                exit 1
            fi

            task_summary=$1
            due_line=''
            if [[ $# -eq 2 && -n $2 ]]; then
                datetime=$2
                if ! due_epoch=$(date -d "$datetime" +%s 2>/dev/null); then
                    echo "Error: Invalid due date: $datetime" >&2
                    exit 1
                fi

                # A date without a time represents an all-day task.
                if [[ "$datetime" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}|today|tomorrow|(next[[:space:]]+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday))$ ]]; then
                    due_line="DUE;VALUE=DATE:$(date -d "@$due_epoch" +%Y%m%d)"
                else
                    due_line="DUE:$(date -u -d "@$due_epoch" +%Y%m%dT%H%M%SZ)"
                fi
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
            nc_app_pass=$(cat "${passwordFile}")
            curl_user=$(escape_curl_config "ubritos@gmail.com:$nc_app_pass")

            ical_lines=(
                "BEGIN:VCALENDAR"
                "VERSION:2.0"
                "PRODID:-//repparw t//EN"
                "BEGIN:VTODO"
                "UID:$task_uid"
                "DTSTAMP:$dtstamp"
                "SUMMARY:$task_text"
            )
            if [[ -n "$due_line" ]]; then
                ical_lines+=("$due_line")
            fi
            ical_lines+=("PRIORITY:9" "PERCENT-COMPLETE:0")
            if [[ -n "$due_line" ]]; then
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

            if ! http_code=$(
                for line in "''${ical_lines[@]}"; do
                    fold_ical_line "$line"
                done |
                    curl -sS -o /dev/null -w '%{http_code}' \
                        --connect-timeout 10 --max-time 30 \
                        --config <(printf 'user = "%s"\n' "$curl_user") \
                        -X PUT \
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
