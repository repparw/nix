{ config, pkgs, ... }:

{
programs.zsh = {
  enable = true;
  enableCompletion = true;
  enableGlobbing = true;
  dotDir = "${config.home.homeDirectory}/.config/zsh";
}

}
