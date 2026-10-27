{ den, ... }:
{
  den.aspects.moonshine-verification.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.moonshineVerification;
      runnerUser = "moonshine-verify";
      runnerUid = 65000;
      devices = [
        cfg.renderNode
        "/dev/uinput"
        "/dev/uhid"
      ];
      lifetimeCheck = pkgs.writeText "moonshine-check-lifetime.py" (
        builtins.readFile ../../tools/moonshine-verification/check-lifetime.py
      );
      markContainerStart = pkgs.writeShellScript "moonshine-container-start.sh" ''
        set -euo pipefail
        ${pkgs.coreutils}/bin/install -d -m 0755 /run/moonshine-verification-lifetime
        ${pkgs.python3}/bin/python3 -c 'import time; print(time.monotonic())' > /run/moonshine-verification-lifetime/start.tmp
        ${pkgs.coreutils}/bin/mv /run/moonshine-verification-lifetime/start.tmp /run/moonshine-verification-lifetime/start
      '';
      trustedJob = pkgs.writeShellScript "moonshine-trusted-job.sh" ''
        set -euo pipefail
        test "''${GITHUB_EVENT_NAME:-}" = workflow_dispatch
        test "''${GITHUB_REPOSITORY:-}" = repparw/nix
        test "''${GITHUB_REF:-}" = refs/heads/main
        test "''${GITHUB_WORKFLOW_REF:-}" = \
          repparw/nix/.github/workflows/moonshine-host-smoke.yml@refs/heads/main
        runner_start=$(${pkgs.systemd}/bin/systemctl show github-runner-moonshine.service \
          --property=ActiveEnterTimestampMonotonic --value)
        ${pkgs.python3}/bin/python3 ${lifetimeCheck} \
          --container-start-file /run/moonshine-verification-lifetime/start \
          --runner-start-us "$runner_start"
      '';
      conflictCheck = pkgs.writeText "moonshine-check-conflicts.py" (
        builtins.readFile ../../tools/moonshine-verification/check-conflicts.py
      );
    in
    {
      options.services.moonshineVerification = {
        enable = lib.mkEnableOption "the manually started Alpha Moonshine verification container";
        tokenFile = lib.mkOption {
          type = lib.types.str;
          default = "/run/secrets/moonshine-verification-runner";
          description = "Runtime SOPS secret containing a runner-registration PAT; never a store path.";
        };
        renderNode = lib.mkOption {
          type = lib.types.str;
          default = "/dev/dri/renderD128";
          description = "Alpha render node exposed to the verification container.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = lib.hasPrefix "/run/secrets/" cfg.tokenFile;
            message = "Moonshine verification tokenFile must be a runtime SOPS secret under /run/secrets/.";
          }
        ];
        # Give the shared, unprivileged host Nix daemon a real peer identity.
        users.groups.${runnerUser}.gid = runnerUid;
        users.users.${runnerUser} = {
          isSystemUser = true;
          uid = runnerUid;
          group = runnerUser;
        };

        containers.moonshine-verification = {
          autoStart = false;
          ephemeral = true;
          privateNetwork = false;
          allowedDevices = map (node: {
            inherit node;
            modifier = "rw";
          }) devices;
          bindMounts =
            lib.genAttrs devices (node: {
              hostPath = node;
              isReadOnly = false;
            })
            // {
              "/run/opengl-driver" = {
                hostPath = "/run/opengl-driver";
                isReadOnly = true;
              };
              "/run/host-proc" = {
                hostPath = "/proc";
                isReadOnly = true;
              };
              "/run/moonshine-verification-lifetime" = {
                hostPath = "/run/moonshine-verification-lifetime";
                isReadOnly = true;
              };
              "/run/secrets/runner-token" = {
                hostPath = cfg.tokenFile;
                isReadOnly = true;
              };
            };
          config = { ... }: {
            system.stateVersion = "26.05";
            networking.hostName = "moonshine-verification";
            services.dbus.enable = true;
            users.groups.${runnerUser}.gid = runnerUid;
            users.groups.render.gid = config.users.groups.render.gid;
            users.groups.input.gid = config.users.groups.input.gid;
            users.users.${runnerUser} = {
              isNormalUser = true;
              uid = runnerUid;
              group = runnerUser;
              extraGroups = [
                "render"
                "input"
              ];
              linger = true;
            };
            services.github-runners.moonshine = {
              enable = true;
              name = "alpha-moonshine-smoke";
              url = "https://github.com/repparw/nix";
              tokenFile = "/run/secrets/runner-token";
              user = runnerUser;
              group = runnerUser;
              ephemeral = true;
              noDefaultLabels = true;
              extraLabels = [ "alpha-moonshine-smoke" ];
              extraPackages = [
                pkgs.git
                pkgs.nix
                pkgs.coreutils
                pkgs.python3
              ];
              extraEnvironment = {
                XDG_RUNTIME_DIR = "/run/user/${toString runnerUid}";
                DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/${toString runnerUid}/bus";
                ACTIONS_RUNNER_HOOK_JOB_STARTED = trustedJob;
                MOONSHINE_CONFLICT_CHECK = "${conflictCheck}";
              };
              serviceOverrides = {
                Restart = lib.mkForce "no";
                RuntimeMaxSec = "25min";
                PrivateUsers = false;
                # The compositor and user-manager-launched app share container sockets.
                PrivateTmp = false;
                ReadWritePaths = [ "/run/user/${toString runnerUid}" ];
                BindPaths = devices;
                DeviceAllow = map (node: "${node} rw") devices;
              };
            };
            systemd.services.github-runner-moonshine = {
              after = [ "user@${toString runnerUid}.service" ];
              requires = [ "user@${toString runnerUid}.service" ];
            };
          };
        };
        systemd.services."container@moonshine-verification" = {
          overrideStrategy = "asDropin";
          serviceConfig = {
            ExecStartPre = [ markContainerStart ];
            RuntimeMaxSec = "30min";
            MemoryMax = "12G";
            CPUQuota = "400%";
          };
        };
      };
    };
}
