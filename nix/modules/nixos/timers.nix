{ pkgs, ... }:

{

  systemd.services.buptohdd = {
	serviceConfig = {
	  Type="oneshot";
	  ExecStart="${pkgs.bashInteractive}/bin/sh ~/.config/scripts/buptohdd";
	};
  };

  systemd.services.git-autocommit = {
	serviceConfig = {
	  Type="oneshot";
	  ExecStart="${pkgs.bashInteractive}/bin/sh ~/.config/scripts/git-autocommit";
	};
  };

  systemd.services.rclone-sync = {
	serviceConfig = {
	  Type="oneshot";
	  ExecStart="${pkgs.rclone}/bin/rclone sync ~/.config/dlsuite crypt:dlsuite";
	};
  };

  systemd.services.docker-cleanup = {
	requires = ["docker.service"];
	wantedBy = ["multi-user.target"];
	after = ["docker.service"];
	serviceConfig = {
	  Type="oneshot";
	  WorkingDirectory="/tmp";
	  User="root";
	  Group="root";
	  ExecStart="${pkgs.docker}/bin/docker system prune -af";
	};
  };

  systemd.timers.buptohdd = {
	wantedBy = ["timers.target"];
	timerConfig = {
	  OnCalendar="* 03:00:00";
	  Persistent=true;
	};
  };

  systemd.timers.git-autocommit = {
	wantedBy = ["timers.target"];
	timerConfig = {
	  OnCalendar="*:0/4";
	  Persistent=true;
	};
  };

  systemd.timers.rclone-sync= {
	wantedBy = ["timers.target"];
	timerConfig = {
	  OnCalendar="*-*-*/7 00:00:00";
	  Persistent=true;
	};
  };

  systemd.timers.docker-cleanup = {
	wantedBy = ["timers.target"];
	timerConfig = {
	  OnCalendar="*-*-*/14 12:00:00";
	  Persistent=true;
	};
  };



}
