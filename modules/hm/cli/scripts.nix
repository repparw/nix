{ pkgs, ... }:
{
  home.packages = with pkgs; [
    (stdenv.mkDerivation {
      pname = "odin4";
      version = "4";

      src = pkgs.fetchzip {
        url = "https://github.com/Adrilaw/OdinV4/releases/download/v1.0/odin.zip";
        hash = "sha256-SoznK53UD/vblqeXBLRlkokaLJwhMZy7wqKufR0I8hI=";
      };

      nativeBuildInputs = [ pkgs.autoPatchelfHook ];

      installPhase = ''
        runHook preInstall
        install -m755 -D odin4 $out/bin/odin4
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
        mpv
      ];
      text = ''
        notify-send -t 2000 'MPV' 'Loading video...'; mpv --no-terminal "$(wl-paste)"
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
  ];
}
