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

    jellyfin-mpv-shim = prev.jellyfin-mpv-shim.overrideAttrs (old: {
      propagatedBuildInputs = builtins.filter (
        pkg: (pkg.pname or "") != "pywebview"
      ) old.propagatedBuildInputs;
    });

  };

  # Keep the stable overlay as is
  stable = final: _: {
    stable = inputs.nixpkgs-stable.legacyPackages.${final.system};
  };
}
