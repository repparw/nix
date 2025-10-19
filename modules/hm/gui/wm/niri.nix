{ lib, osConfig, ... }:
{
  config = lib.mkIf osConfig.programs.niri.enable {
    # keybinds, etc
  };
}
