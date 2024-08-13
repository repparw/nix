{ pkgs, ... }:

{
  home.packages = with pkgs; [
		# Gaming
#		TODO steam
		heroic
		lutris
		mangohud
  	];
}
