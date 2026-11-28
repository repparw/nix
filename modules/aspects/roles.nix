{ den, ... }:
{
  den.aspects.workstation = {
    includes = [
      den.aspects.desktop
      den.aspects.gaming
      den.aspects.streaming
    ];

    nixos = { lib, ... }: {
      networking.wireless.iwd = {
        enable = true;
        settings = {
          General.AddressRandomization = "network";
          Settings.AutoConnect = true;
        };
      };
      systemd.services.iwd.wantedBy = lib.mkForce [ ];
    };
  };

  den.aspects.managed-server = {
    includes = [
      den.aspects.monitoring._.persist
      den.aspects.passwordless-sudo
      den.aspects.persistence
    ];

    # Always select the CLI on headless hosts. Until nixpkgs#555814 is pinned,
    # the temporary upstream overlay provides t3code-server instead.
    provides.to-users.homeManager = { pkgs, ... }: {
      programs.t3code.package = if pkgs ? t3code-cli then pkgs.t3code-cli else pkgs.t3code-server;
    };
  };
}
