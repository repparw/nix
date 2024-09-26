{ hostName, ... }:

{
  imports = [
    ../modules/nixos/cachix.nix
    ../modules/nixos/common.nix
    ../modules/nixos/hyprland.nix
    ./${hostName}
  ];

  programs.nh = {
    enable = true;
    flake = "/home/repparw/.dotfiles/nix";
    clean = {
      enable = true;
      extraArgs = "--keep 3 -keep-since 7d";
    };
  };

  services.vdirsyncer = {
    enable = true;
    jobs.gcal = {
      enable = true;
      timerConfig = {
        OnBootSec = "1h";
        OnUnitActiveSec = "2h";
      };
	  config.storages = {
		my_cloud_contacts = {
		  type = "carddav";
		  url = "https://dav.example.com/";
		  read_only = true;
		  username = "user";
		  "password.fetch" = [ "command" "cat" "/etc/vdirsyncer/cloud.passwd" ];
		};
    };
  };

  nix.trustedUsers = [
    "root"
    "repparw"
  ];

  nix.optimise.automatic = true;

  nixpkgs.config.allowUnfree = true;

  hardware.xpadneo.enable = true;

}
