{
  den,
  ...
}:
{
  den.aspects.scripts = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [

          (writeShellApplication {
            name = "clip2qr";
            runtimeInputs = [
              wl-clipboard
              zbar
            ];
            text = ''
              wl-paste --type image/png | zbarimg --raw - | wl-copy
            '';
          })

          (writeShellApplication {
            name = "hotswap";
            text = ''
              if [ $# -eq 0 ]; then
                echo "Usage: hotswap <file>"
                exit 1
              fi

              file="$1"

              if [ ! -e "$file" ]; then
                echo "Error: File '$file' does not exist"
                exit 1
              fi

              if [ ! -L "$file" ]; then
                echo "File is not a symlink, nothing to do"
                exit 1
              fi

              target="$(readlink -f "$file")"
              temp="$(mktemp)"

              cp "$target" "$temp"

              if nvim "$temp"; then
                rm "$file"
                mv "$temp" "$file"
                echo "Saved."
              else
                rm "$temp"
                echo "Edit canceled."
              fi
            '';
          })

        ];
      };
  };
}
