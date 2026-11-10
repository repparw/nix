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

  den.aspects.headless-user.includes = [
    den.aspects.repparw
    den.aspects.ai._.t3code-split
  ];
  # Shared NixOS capabilities of the two headless managed hosts.
  # Hardware, network addresses, and actual services stay host-owned.
  den.aspects.managed-server.includes = [
    den.aspects.monitoring._.persist
    den.aspects.passwordless-sudo
    den.aspects.persistence
  ];
}
