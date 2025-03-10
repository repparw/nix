{ ... }:
{
  system.autoUpgrade = {
    enable = true;
    flake = "github:repparw/dotfiles/nix";
    flags = [
      "--update-input"
      "nixpkgs"
      "-L" # print build logs
    ];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };
}
