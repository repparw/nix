{ ... }:
{
  system.autoUpgrade = {
    enable = true;
    flake = "github:repparw/nix";
    flags = [
      "--commit-lock-file"
      "-L"
    ];
    dates = "04:40";
    persistent = true;
    randomizedDelaySec = "45min";
  };
}
