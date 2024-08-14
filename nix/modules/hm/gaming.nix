{ pkgs, ... }:

{
  home.packages = with pkgs; [
		# Gaming
		heroic
		lutris
		mangohud
  	];
}
