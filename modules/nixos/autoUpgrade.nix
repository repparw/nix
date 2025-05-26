{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  flakePath = "/home/repparw/nix"; # can't be outPath because flake update updates the wrong one
in
{
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
    flake = "${flakePath}";
    flags = [
      "-L"
    ];
    dates = "04:40";
    persistent = true;
    randomizedDelaySec = "45min";
  };

  systemd.services.nixos-upgrade = {
    after = [ "flake-update.service" ];
    wants = [ "flake-update.service" ];
  };

  # Write git config directly during system activation
  system.activationScripts.rootGitConfig = ''
    mkdir -p /root
    cat > /root/.gitconfig << EOF
    [safe]
        directory = /home/repparw/nix
    EOF
  '';
}
