{ pkgs, ... }:
{

  home.packages = with pkgs; [

    (writeShellApplication {
      name = "bttoggle";
      runtimeInputs = [ bluez ];
      text = ''
        device=F8:4E:17:E6:22:D2

        if [ -n "$(bluetoothctl devices Connected)" ]; then
          bluetoothctl disconnect
        else
          bluetoothctl connect "$device"
        fi
      '';
    })

    (writeShellApplication {
      name = "git-autocommit";
      runtimeInputs = [ git ];
      text = ''
        DIR=${"1:-/home/repparw/nix"}
        cd "$DIR" || exit 1
        git add -A
        git commit -m "Autocommit"
        git pull --rebase
        git push
      '';
    })

    (writeShellApplication {
      name = "mpvclip";
      runtimeInputs = [
        tmux
        mpv
        nq
      ];
      text = ''
        	  tmux new-session -d -s mpv; tmux send-keys -t mpv "  NQDIR=/tmp/nq/tmux nq -cq mpv --no-terminal $(wl-paste)" C-m
      '';
    })

    (writeShellApplication {
      name = "obsinvim";
      text = ''
        cd /home/repparw/Documents/obsidian; $EDITOR .
      '';
    })

    (writeShellApplication {
      name = "obs_remux2wsp";
      runtimeInputs = [ ffmpeg ];
      text = ''
        		cd /mnt/hdd/Videos/obs;
        		FILE=$(find '.' ./*.mkv -maxdepth 0 -type f -printf '%T@ %p
        ' | sort -k 1nr | sed 's/^[^ ]* //' | head -n 1
        )
        		ffmpeg -sseof -60 -i "$FILE" -vcodec libx264 -ac 1 -acodec copy -pix_fmt yuv420p "''${FILE%.*}".mp4;
      '';
    })

    (writeShellApplication {
      name = "update";
      runtimeInputs = [
        kitty
        nh
      ];
      text = ''
        	 kitty --hold zsh -c " nh os switch -u"
        	 '';
    })

  ];
}
