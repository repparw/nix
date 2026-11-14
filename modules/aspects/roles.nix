{ den, ... }:
{
  # User-side composition, separate from host hardware and service roles.
  # Only the workstation user receives desktop, gaming and streaming settings.
  den.aspects.workstation-user.includes = [
    den.aspects.repparw
    den.aspects.desktop
    den.aspects.gaming
    den.aspects.streaming
  ];

  den.aspects.headless-user = {
    includes = [ den.aspects.repparw ];

    # Always select the CLI on headless hosts. Until nixpkgs#555814 is pinned,
    # the temporary upstream overlay provides t3code-server instead.
    homeManager = { pkgs, ... }: {
      programs.t3code.package = if pkgs ? t3code-cli then pkgs.t3code-cli else pkgs.t3code-server;
    };
  };

  # Shared NixOS capabilities of the two headless managed hosts.
  # Hardware, network addresses, and actual services stay host-owned.
  den.aspects.managed-server.includes = [
    den.aspects.monitoring._.persist
    den.aspects.passwordless-sudo
    den.aspects.persistence
  ];
}
