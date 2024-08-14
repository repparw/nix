{ pkgs, ... }:
{

  systemd.services.buptohdd = {
	serviceConfig = {
	  Type="oneshot";
	  User="repparw";
	  ExecStart="${pkgs.rsync}/bin/rsync -aq --delete /home/repparw/Pictures /home/repparw/Documents /home/repparw/.config --exclude='dlsuite' /mnt/hdd/backup";
	};
  };

  systemd.services.git-autocommit = {
	serviceConfig = {
	  WorkingDirectory="/home/repparw/.dotfiles";
	  Type="oneshot";
	  User="repparw";
	  ExecStart=["${pkgs.git}/bin/git add -A" "${pkgs.git}/bin/git diff-index --quiet --cached HEAD || ${pkgs.git}/bin/git commit -m Autocommit" "${pkgs.git}/bin/git push" ];
	};
  };

  systemd.services.rclone-sync = {
	serviceConfig = {
	  Type="oneshot";
	  User="repparw";
	  ExecStart="${pkgs.rclone}/bin/rclone sync /home/repparw/.config/dlsuite crypt:dlsuite";
	};
  };

  systemd.services.docker-cleanup = {
	requires = ["docker.service"];
	wantedBy = ["multi-user.target"];
	after = ["docker.service"];
	serviceConfig = {
	  Type="oneshot";
	  User="repparw";
	  WorkingDirectory="/tmp";
	  ExecStart="${pkgs.docker}/bin/docker system prune -af";
	};
  };

  systemd.timers.buptohdd = {
	wantedBy = ["timers.target"];
	timerConfig = {
	  OnCalendar="03:00:00";
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
	  OnCalendar="*-*-7,14,21,28 00:00:00";
	  Persistent=true;
	};
  };

  systemd.timers.docker-cleanup = {
	wantedBy = ["timers.target"];
	timerConfig = {
	  OnCalendar="*-*-1,15 12:00:00";
	  Persistent=true;
	};
  };



}
