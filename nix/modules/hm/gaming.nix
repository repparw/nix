{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Gaming
    lutris
    heroic
    mangohud
  ];
}
