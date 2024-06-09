{ inputs, config, lib, pkgs, hostName, ... }:

let
  # alpha equals true if hostname is alpha, else false
  alpha = (hostName == "alpha");
in
{
  imports = [
	./hypr-programs.nix
	./hypr-binds.nix
	./hypr-pkgs.nix
  ];

  wayland.windowManager.hyprland = {
	enable = true;
	package = pkgs.hyprland;
	xwayland.enable = true;
	systemd.enable = true;
	extraConfig = ''
	  ${builtins.readFile ./hyprland.conf}
	''
	if alpha then
	extraConfig = ''
	  ${builtins.readFile ./binds-alpha.conf}
	''
	else
	extraConfig = ''
	  ${builtins.readFile ./binds-beta.conf}
	''
	};
}
