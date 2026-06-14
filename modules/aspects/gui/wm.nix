{
  den,
  lib,
  ...
}:
{
  den.aspects.gui.provides.wm = {
    homeManager =
      { config, pkgs, ... }:
      let
        todoExtension = pkgs.runCommandLocal "vicinae-todo-extension" { } ''
          mkdir -p "$out"
          cp ${
            pkgs.writeText "vicinae-todo-package.json" (
              builtins.toJSON {
                "$schema" =
                  "https://raw.githubusercontent.com/vicinaehq/vicinae/refs/heads/main/extra/schemas/extension.json";
                name = "todo";
                title = "Todo";
                description = "Create tasks with the local t wrapper";
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
      in
      {
        home.packages = with pkgs; [
          wl-clipboard
          nautilus
          baobab
          playerctl
        ];

        services = {
          swayidle = {
            enable = true;
            timeouts = [
              {
                timeout = 900;
                command = "${lib.getExe pkgs.niri} msg action power-off-monitors";
              }
              {
                timeout = 915;
                command = "${lib.getExe' pkgs.systemd "loginctl"} lock-session";
              }
            ];
            events = {
              before-sleep = "${lib.getExe' pkgs.systemd "loginctl"} lock-session";
              lock = "${lib.getExe pkgs.swaylock} -f";
              unlock = "${lib.getExe' pkgs.procps "pkill"} -USR1 swaylock";
            };
          };

          hyprpolkitagent.enable = true;

          wlsunset = {
            enable = true;
            temperature.night = 2500;
            latitude = -35.1;
            longitude = -59.8;
          };

          swaync = {
            enable = true;
            settings = {
              timeout-critical = 20000;
            };
          };
          playerctld.enable = true;
        };

        programs = {
          swaylock.enable = true;

          vicinae = {
            enable = true;
            systemd.enable = true;
            extensions = [ todoExtension ];
          };

          ashell = {
            enable = true;
            systemd.enable = true;
            settings = {
              outputs = {
                Targets = [ "HDMI-A-1" ];
              };
              modules = {
                left = [ "Clock" ];
                center = [ "MediaPlayer" ];
                right = [
                  "Tray"
                  "Settings"
                  "CustomNotifications"
                ];
              };
              CustomModule = [
                {
                  name = "CustomNotifications";
                  icon = "";
                  command = "swaync-client -t -sw";
                  listen_cmd = "swaync-client -swb";
                  alert = ".*notification";
                }
              ];
              appearance = {
                style = "Islands";
                opacity = 1.0;
                menu = {
                  opacity = lib.mkForce 0.95;
                  backdrop = 0.3;
                };
              };
            };
          };
        };

        xdg.configFile."vicinae/settings.json".enable = lib.mkForce false;
      };
  };
}
