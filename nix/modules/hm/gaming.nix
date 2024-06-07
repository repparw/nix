{ inputs, config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
		# Gaming
		steam
		heroic
		lutris
		mangohud
  	];
}
