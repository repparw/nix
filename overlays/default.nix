{ inputs, ... }:
{
  modifications = final: prev: {
    mpv = prev.mpv.override {
      scripts = with prev.mpvScripts; [
        mpv-webm
        mpris
        quality-menu
        sponsorblock-minimal
      ];
    };
    neovim = inputs.nixvim-config.packages.${prev.system}.default;

    hyprlandPlugins = prev.hyprlandPlugins // {
      hyprsplit = prev.hyprlandPlugins.hyprsplit.overrideAttrs (
        old:
        let
          version = "0.51.1";
        in
        {
          inherit version;
          src = prev.fetchFromGitHub {
            owner = "shezdy";
            repo = "hyprsplit";
            tag = "v${version}";
            hash = "sha256-7cnfq7fXgJHkmHyvRwx8UsUdUwUEN4A1vUGgsSb4SmI=";
          };
        }
      );
    };

  };

  # Keep the stable overlay as is
  stable = final: _: {
    stable = inputs.nixpkgs-stable.legacyPackages.${final.system};
  };
}
