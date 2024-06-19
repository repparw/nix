{ pkgs, ... }:

{

  programs.hyprland = { 
	enable = true;
  };

  environment.systemPackages = [
    pkgs.kdePackages.polkit-kde-agent-1 # launch?
  ];

  services.greetd = {
	enable = true;
	vt = 1;
	settings = rec {
	  initial_session = {
	   command = "${pkgs.hyprland}/bin/Hyprland";
	   user = "repparw";
		};
	  default_session = initial_session;
	 };
  };

}
