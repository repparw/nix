{ ... }:

{
  services.kanshi = {
	enable = true;
	systemdTarget = "hyprland-session.target";
	settings = [
	  { profile.name = "undocked";
		profile.outputs = [{
			criteria = "eDP-1";
		  }];
	  }
	  { profile.name = "docked";
		profile.outputs = [{
		  criteria = "eDP-1";
		  status = "disable";
		}
		{
		 criteria = "ViewSonic Corporation XG2401 SERIES UG2174400580";
		}
	  ];
	  }
	];
  };
}
