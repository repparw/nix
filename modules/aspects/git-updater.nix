{
  den,
  ...
}:
{
  den.aspects.git-updater = {
    includes = [ den.aspects.git ];

    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        projectsDir = config.xdg.userDirs.projects;
        fetchProjects = pkgs.writeShellApplication {
          name = "git-fetch-projects";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.git
          ];
          text = ''
            projects="''${1:?projects directory required}"
            export GIT_TERMINAL_PROMPT=0
            export GIT_SSH_COMMAND="ssh -oBatchMode=yes -oConnectTimeout=15"

            failures=0
            count=0
            for dir in "$projects"/*/; do
              # Clones only: worktrees share their main checkout's object
              # store, so fetching the main repo covers them.
              [ -d "$dir/.git" ] || continue
              [ -n "$(git -C "$dir" remote)" ] || continue
              count=$((count + 1))
              name=''${dir%/}
              name=''${name##*/}
              if out=$(timeout 300 git -C "$dir" fetch --prune --quiet 2>&1); then
                printf 'ok %s\n' "$name"
              else
                printf 'failed %s: %s\n' "$name" "$out"
                failures=$((failures + 1))
              fi
            done
            printf 'fetched %d repos under %s (%d failures)\n' "$count" "$projects" "$failures"
            [ "$failures" -eq 0 ]
          '';
        };
      in
      {
        systemd.user.services.git-fetch-projects = {
          Unit.Description = "Fetch git repositories under ${projectsDir}";
          Service = {
            Type = "oneshot";
            ExecStart = "${lib.getExe fetchProjects} ${projectsDir}";
          };
        };

        systemd.user.timers.git-fetch-projects = {
          Unit.Description = "Periodically fetch git repositories";
          Timer = {
            OnStartupSec = "10min";
            OnUnitActiveSec = "24h";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
  };
}
