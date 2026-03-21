{
  den,
  lib,
  pkgs,
  ...
}:
{
  den.aspects.gui.provides.niri = {
    nixos =
      { pkgs, ... }:
      {
        programs.niri.enable = lib.mkDefault true;

        environment.systemPackages = [ pkgs.xwayland-satellite ];
      };

    homeManager =
      { config, ... }:
      {
        xdg.configFile."niri/config.kdl".source = config.lib.file.mkOutOfStoreSymlink ./config.kdl;

        services.wpaperd.enable = true;
      };
  };
}
