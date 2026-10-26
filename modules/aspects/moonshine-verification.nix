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
      trustedJob = pkgs.writeShellScript "moonshine-trusted-job.sh" ''
        set -euo pipefail
        test "''${GITHUB_EVENT_NAME:-}" = workflow_dispatch
        test "''${GITHUB_REPOSITORY:-}" = repparw/nix
        test "''${GITHUB_REF:-}" = refs/heads/main
        test "''${GITHUB_WORKFLOW_REF:-}" = \
          repparw/nix/.github/workflows/moonshine-host-smoke.yml@refs/heads/main
      '';
      hostIdle = pkgs.writeShellScript "moonshine-verification-host-idle.sh" ''
        set -euo pipefail
        operator_uid=$(${pkgs.coreutils}/bin/id -u ${lib.escapeShellArg cfg.operatorUser})
        state=$(${pkgs.util-linux}/bin/runuser -u ${lib.escapeShellArg cfg.operatorUser} -- \
          ${pkgs.coreutils}/bin/env XDG_RUNTIME_DIR="/run/user/$operator_uid" \
          DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$operator_uid/bus" \
          ${pkgs.systemd}/bin/systemctl --user show moonshine-session.service \
          --property=ActiveState --value)
        test "$state" = inactive
        for session in $(${pkgs.systemd}/bin/loginctl show-user \
          ${lib.escapeShellArg cfg.operatorUser} --property=Sessions --value); do
          kind=$(${pkgs.systemd}/bin/loginctl show-session "$session" --property=Type --value)
          if test "$kind" = wayland || test "$kind" = x11; then
            test "$(${pkgs.systemd}/bin/loginctl show-session "$session" --property=IdleHint --value)" = yes
          fi
        done
      '';
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
        operatorUser = lib.mkOption {
          type = lib.types.str;
          default = "repparw";
          description = "Desktop user whose stream and graphical idle state gate container startup.";
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
              ];
              extraEnvironment = {
                XDG_RUNTIME_DIR = "/run/user/${toString runnerUid}";
                DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/${toString runnerUid}/bus";
                ACTIONS_RUNNER_HOOK_JOB_STARTED = trustedJob;
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
            ExecCondition = hostIdle;
            RuntimeMaxSec = "30min";
            MemoryMax = "12G";
            CPUQuota = "400%";
          };
        };
      };
    };
}
