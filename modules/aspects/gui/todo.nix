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
            if [ "$#" -eq 0 ]; then
                echo "Usage: t \"TASK SUMMARY\" [DATETIME]"
                echo "Example: t \"Buy milk\" \"tomorrow 9am\""
                exit 1
            fi

            if [ ! -f "${passwordFile}" ]; then
                echo "Error: Nextcloud secret file not found at ${passwordFile}" >&2
                exit 1
            fi
            nc_app_pass=$(cat "${passwordFile}")

            task_summary="$*"
            datetime="tomorrow 9am"

            if date -d "''${!#}" > /dev/null 2>&1; then
                datetime="''${!#}"
                task_summary="''${*:1:$#-1}"
            fi

            is_midnight=$(date -d "$datetime" +%H%M)
            if [ "$is_midnight" = "0000" ]; then
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
            PRODID:-//repparw t//EN
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

            http_code=$(curl -s -o /dev/null -w '%{http_code}' \
                -X PUT \
                --user "ubritos@gmail.com:$nc_app_pass" \
                -H "Content-Type: text/calendar; charset=utf-8" \
                --data-raw "$ICAL_DATA" \
                "${caldavList}/$FILE_NAME")

            if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
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
