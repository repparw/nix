{
  pkgs,
  inputs,
  lib,
  ...
}: {
  system.autoUpgrade = {
    enable = true;
    flake = "github:repparw/nix";
    dates = "02:00";
  };

  # Service to update flake lock file
  systemd.services.flake-update = {
    description = "Update Nix flake lock file";
    path = with pkgs; [git];
    serviceConfig = {
      WorkingDirectory = inputs.self.outPath;
      Type = "oneshot";
      ExecStart = "${lib.getExe pkgs.nix} flake update --commit-lock-file";
    };
  };
  systemd.services.nixos-upgrade = {
    after = ["flake-update.service"];
    requires = ["flake-update.service"];
  };
}
