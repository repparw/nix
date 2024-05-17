{ config, pkgs, ... }:

{

programs.zsh = {
  enable = true;
  enableCompletion = true;
  enableGlobbing = true;
}

}
