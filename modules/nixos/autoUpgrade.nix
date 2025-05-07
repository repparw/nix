{
  pkgs,
  lib,
  inputs,
  ...
}: let
  flakePath = inputs.self.outPath;
in {
  ## Update flake inputs daily
  systemd.services = {
    flake-update = {
      unitConfig = {
        Description = "Update flake inputs";
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      };
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.nix} flake update --commit-lock-file --flake ${flakePath}";
        Restart = "on-failure";
        RestartSec = "30";
        Type = "oneshot"; # Ensure that it finishes before starting nixos-upgrade
      };
    };
  };

  system.autoUpgrade = {
    enable = true;
    flake = "${flakePath}#${config.networking.hostName}";
    flags = [
      "-L"
    ];
    dates = "04:40";
    persistent = true;
    randomizedDelaySec = "45min";
  };

  systemd.services.nixos-upgrade = {
    after = ["flake-update.service"];
    wants = ["flake-update.service"];
  };
}
