{ pkgs, ... }:
{

  home.packages = with pkgs; [

    (stdenv.mkDerivation {
      pname = "odin4";
      version = "4";

      src = pkgs.fetchzip {
        url = "https://github.com/Adrilaw/OdinV4/releases/download/v1.0/odin.zip";
        hash = "sha256-ECuMA6EPfbL96U5But0rz8KeAzizGKOsDG7NO1lbkJc=";
      };

      nativeBuildInputs = [ pkgs.autoPatchelfHook ];

      sourceRoot = ".";

      installPhase = ''
        install -m755 -D odin4 $out/bin/odin
      '';
    })

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
