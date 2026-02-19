{
  lib,
  osConfig,
  ...
}:
{
  config = lib.mkIf osConfig.programs.niri.enable {
    # home.packages = [ pkgs.niri ];

    # use hm module when merged https://github.com/nix-community/home-manager/pull/8700

    # xdg.configFile."niri/config.kdl".source = config.lib.file.mkOutOfStoreSymlink ./config.kdl;
  };
}
