{ inputs, ... }:
{
  flake-file.inputs.impermanence = {
    url = "github:nix-community/impermanence";
    flake = false;
  };

  # This aspect records the first, deliberately conservative persistence set.
  # Hosts still need a migrated /persist volume and a separate root-layout
  # change before enabling it. Merely including the aspect moves no data.
  den.aspects.persistence.nixos =
    { config, lib, ... }:
    let
      cfg = config.modules.persistence;
    in
    {
      imports = [ (inputs.impermanence + "/nixos.nix") ];

      options.modules.persistence.enable = lib.mkEnableOption "the prepared host persistence mounts";

      config = {
        assertions = [
          {
            assertion = !cfg.enable || (config.fileSystems."/persist".neededForBoot or false);
            message = "Host persistence requires a migrated /persist filesystem with neededForBoot = true; see docs/runbooks/host-persistence.md.";
          }
        ];

        environment.persistence."/persist" = {
          enable = cfg.enable;
          hideMounts = true;
          directories = [
            "/etc/ssh"
            "/var/lib/nixos"
            # Keep existing container roots until each service has passed
            # an independent ephemeral-container restart/restore test.
            "/var/lib/nixos-containers"
            "/var/lib/systemd/timers"
            {
              directory = "/root";
              mode = "0700";
            }
            {
              directory = "/var/lib/fail2ban";
              mode = "0750";
            }
            {
              directory = "/var/lib/systemd/timesync";
              user = "systemd-timesync";
              group = "systemd-timesync";
            }
          ]
          ++ lib.optionals config.services.traefik.enable [
            {
              directory = "/var/lib/traefik";
              user = "traefik";
              group = config.users.users.traefik.group;
              mode = "0700";
            }
          ];
          files = [
            "/etc/machine-id"
            {
              file = "/var/lib/systemd/random-seed";
              method = "symlink";
            }
          ];
        };

        # User-password secrets must decrypt before users are created. Read
        # the key from the early backing mount instead of waiting for /etc/ssh.
        sops.age.sshKeyPaths = lib.mkIf cfg.enable (
          lib.mkForce [ "/persist/etc/ssh/ssh_host_ed25519_key" ]
        );
        fileSystems."/".neededForBoot = lib.mkIf cfg.enable true;
      };
    };
}
