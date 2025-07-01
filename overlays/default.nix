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
      hyprspace = prev.hyprlandPlugins.hyprspace.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./hyprspace.patch ];
      });
    };
  };

  # Keep the stable overlay as is
  stable = final: _: {
    stable = inputs.nixpkgs-stable.legacyPackages.${final.system};
  };
}
