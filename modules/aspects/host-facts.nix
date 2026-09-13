{
  den,
  inputs,
  lib,
  ...
}:
{
  flake-file.inputs.host-facts = {
    url = "path:/home/repparw/.config/nix/private-facts";
    flake = false;
  };

  den.aspects.host-facts = {
    nixos =
      { config, lib, ... }:
      let
        factsPath = "${inputs.host-facts}/facts.nix";
        facts = if builtins.pathExists factsPath then import factsPath else { };
      in
      {
        options.modules.host-facts = {
          # Home WAN/static IPv4. Only epsilon consumes this at eval time
          # (firewall allowlists + WireGuard endpoint). Absent in CI, where
          # evaluation must still succeed and no firewall is deployed.
          wanIp = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = facts.wanIp or null;
            description = "Home WAN/static IPv4; read from the private host-facts flake input, null in CI.";
          };

          # Glance weather widget location. Coarse public default; the precise
          # town lives in the private host-facts file.
          weatherLocation = lib.mkOption {
            type = lib.types.str;
            default =
              if (facts.weatherLocation or null) != null then
                facts.weatherLocation
              else
                "Buenos Aires, Argentina";
            description = "Glance weather widget location.";
          };

          # Bluetooth device MAC targeted by `bttoggle`. Exported as
          # TOGGLE_BT_DEVICE; the helper fails clearly when unset.
          bluetoothDevice = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = facts.bluetoothDevice or null;
            description = "Bluetooth device MAC for bttoggle (private host-facts).";
          };

          # Claro Drive WebDAV account identifier, baked into the rclone config
          # at evaluation time (the Home Manager rclone module writes `user`
          # literally).
          clarodriveUser = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = facts.clarodriveUser or null;
            description = "Claro Drive account identifier for the rclone `claro` remote.";
          };
        };
      };
  };
}
