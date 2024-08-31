{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Gaming
    lutris
    mangohud
  ];
}
