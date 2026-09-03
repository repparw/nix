{
  den,
  pkgs,
  lib,
  ...
}:
{
  den.aspects.shell = {
    nixos = {
      programs.fish = {
        enable = true;
        useBabelfish = true;
      };
    };

    homeManager =
      {
        osConfig,
        pkgs,
        lib,
        ...
      }:
      let
        # Gated manual update: probe -> GC headroom -> diff
        # review -> flip -> soak -> rollback. Consumers pull and flip;
        # input bumps belong to pi's auto-update pipeline. PROBE overrides
        # the built-in gate with a stricter external check (pi's pipeline
        # sets it to the fleet-health probe).
        host-update = pkgs.writeShellApplication {
          name = "host-update";
          runtimeInputs = with pkgs; [
            git
            nix
            nixos-rebuild
            nvd
            curl
            gawk
            gnugrep
            coreutils
            sudo
          ];
          text = ''
                        set -u
                        flake="''${FLAKE:-$HOME/Projects/nix}"
                        host=$(cat /etc/hostname)
                        yes=0
                        no_pull=0
                        result=""

                        # Flags: --yes flips without prompting (headless callers),
                        # --no-pull leaves tree management to the caller, --result=PATH
                        # diffs a prebuilt closure instead of building (skips GC too).
                        for a in "$@"; do
                          case "$a" in
                            --yes) yes=1 ;;
                            --no-pull) no_pull=1 ;;
                            --result=*) result="''${a#--result=}" ;;
                            *)
                              echo "unknown arg: $a"
                              exit 2
                              ;;
                          esac
                        done

                        gate() {
                          if [ -n "''${PROBE:-}" ]; then
                            "$PROBE" --strict --local
                          else
                            # "degraded" is acceptable (alpha carries benign failed
                            # user noise); only a failed manager blocks. Pi is probed
                            # by TCP on its edge port: post-migration its traefik
                            # serves LAN vhosts over 443 only, no plain http.
                            state=$(systemctl is-system-running 2>/dev/null || true)
                            case "$state" in
                              running | degraded) ;;
                              *) return 1 ;;
                            esac
                            timeout 3 bash -c 'exec 3<>/dev/tcp/192.168.0.4/443' 2>/dev/null
                          fi
                        }

                        if ! gate; then
                          echo "health gate failing; fix before updating"
                          exit 1
                        fi

                        cd "$flake"

                        # Consumers pull; pi pushes. Never bump inputs here.
                        if [ "$no_pull" = 0 ]; then
                          git fetch origin main
                          behind=$(git rev-list --count HEAD..origin/main || echo 0)
                          if [ "$behind" -gt 0 ]; then
                            if [ -z "$(git status --porcelain)" ]; then
                              git merge --ff-only origin/main
                            else
                              # Carry WIP onto main when it applies cleanly;
                              # otherwise keep WIP in the stash and build main.
                              git stash push -m "host-update carry" >/dev/null
                              if git merge --ff-only origin/main 2>/dev/null; then
                                if git stash apply >/dev/null 2>&1; then
                                  git stash drop >/dev/null
                                  echo "note: carried local WIP onto origin/main"
                                else
                                  git reset --hard origin/main
                                  echo "note: WIP conflicts with main; kept in stash@{0}; building main"
                                fi
                              else
                                git stash pop >/dev/null 2>&1 || true
                                echo "note: local history diverged; building local state"
                              fi
                            fi
                          fi
                        fi

                        if [ -z "$result" ]; then
                          free_kb=$(df -k /nix | awk 'NR==2 {print $4}')
                          if [ "$free_kb" -lt $((10 * 1024 * 1024)) ]; then
                            echo "below 10G on /nix; running gc (sudo password may be asked)"
                            sudo nix-collect-garbage -d || true
                          fi

                          nix build ".#nixosConfigurations.$host.config.system.build.toplevel" \
                            -o /tmp/host-update-result
                          result=/tmp/host-update-result
                        fi

                        nvd diff /run/current-system "$result" \
                          | tee /tmp/host-update-diff.txt
            changed=$(grep -cE '^[<>] ' /tmp/host-update-diff.txt || true)
                        if [ "$changed" -eq 0 ]; then
                          echo "already at the pinned generation"
                          # Exit 3 = no-op: callers stay silent instead of reporting a
                          # flip that did not happen.
                          exit 3
                        fi

                        if [ "$yes" = 0 ]; then
                          printf '\nFlip %s to this generation? [y/N] ' "$host"
                          read -r answer
                          [ "$answer" = "y" ] || {
                            echo "aborted; nothing flipped"
                            exit 1
                          }
                        fi

                        # Headless callers already run as root; interactive users sudo.
                        if [ "$(id -u)" = 0 ]; then
                          nixos-rebuild switch --flake ".#$host"
                        else
                          sudo nixos-rebuild switch --flake ".#$host"
                        fi

                        # Soak: settle, then two consecutive clean gate passes.
                        sleep 45
                        passes=0
                        i=0
                        while [ "$i" -lt 10 ]; do
                          if gate; then
                            passes=$((passes + 1))
                          else
                            passes=0
                          fi
                          [ "$passes" -ge 2 ] && break
                          i=$((i + 1))
                          sleep 30
                        done

                        if [ "$passes" -lt 2 ]; then
                          echo "soak failed; rolling back"
                          if [ "$(id -u)" = 0 ]; then
                            nixos-rebuild switch --rollback
                          else
                            sudo nixos-rebuild switch --rollback
                          fi
                          exit 1
                        fi

                        echo "soak clean; $host updated"
          '';
        };
      in
      {
        home.packages = [ host-update ];

        programs = {
          btop.enable = true;

          direnv = {
            enable = true;
            nix-direnv.enable = true;
            silent = true;
          };

          fish = {
            plugins = with pkgs.fishPlugins; [
              {
                name = "pure";
                inherit (pure) src;
              }
              {
                name = "plugin-git";
                inherit (plugin-git) src;
              }
              {
                name = "done";
                inherit (done) src;
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
            binds = {
              "ctrl-y" = {
                mode = "insert";
                command = "accept-autosuggestion";
              };
              "ctrl-e" = {
                mode = "insert";
                command = "y";
              };
              "ctrl-backspace".command = "backward-kill-word";
              "ctrl-backspace-ins" = {
                name = "ctrl-backspace";
                mode = "insert";
                command = "backward-kill-word";
              };
              "yy".command = "fish_clipboard_copy";
            };
            functions = {
              fish_mode_prompt = "";
              timer = ''
                set label $argv[2]
                test -z "$label"; and set label "▓▓▓"

                fish -c "sleep $argv[1] && notify-send -i 'task-due' -u critical $label" &> /dev/null
              '';
            };
            shellAliases = {
              vo = "cd ~/Documents/obsidian/ && $EDITOR .; prevd";

              vn = "cd ${osConfig.programs.nh.flake}; $EDITOR flake.nix";

              # Alpha is a consumer: pi owns flake.lock (sole writer). The
              # manual path runs the gated host-update wrapper (probe, GC
              # headroom, diff review, soak, rollback) — it never bumps
              # inputs. Raw nrs/nrb stay for one-off local builds.
              nrs = "nh os switch";
              nrb = "nh os boot";
              nrt = "nh os test";

              nrsu = "host-update";
              nrbu = "nrb";

              ln = "ln -i";
              mv = "mv -i";

              rg = "rga";
              rt = "trash put";

              chown = "chown --preserve-root";
              chmod = "chmod --preserve-root";
              chgrp = "chgrp --preserve-root";
              top = "btop";
            }
            // (with pkgs; {
              diff = "${lib.getExe colordiff}";
              cat = "${lib.getExe bat}";
              df = "${lib.getExe duf} -hide-mp /home/containers/\\* -only local";
              du = "${lib.getExe dust}";

              rpi = "${lib.getExe' mosh "mosh"} -P 60001 pi";
              pc = "${lib.getExe' mosh "mosh"} -P 60000 alpha";
              eps = "${lib.getExe' mosh "mosh"} -P 60002 epsilon";

              ns = "${lib.getExe nix-search-tv} print | fzf --preview '${lib.getExe nix-search-tv} preview {}' --scheme history";
            });
            preferAbbrs = true;
            shellAbbrs = {
              su = "sudo -s";

              v = "nvim";

              meminfo = "free -hlt";
              cpuinfo = "lscpu";

              md = "mkdir -pv";

              btctl = "bluetoothctl";

              sys = "systemctl";
              sysu = "systemctl --user";
              syslist = "systemctl list-unit-files";

              cl = "sudo nixos-container list";
              crs = "sudo nixos-container restart";
              csh = "sudo nixos-container root-login";
              crun = "sudo nixos-container run";
              clo = "journalctl -xeu 'container@*'";
              cps = "systemctl list-units 'container@*'";
              cst = "sudo systemctl start container@";
              csp = "sudo systemctl stop container@";
            };
          };
        };
      };
  };
}
