{ inputs, ... }:
{
  modifications = final: prev: {
    mpv-unwrapped = prev.mpv-unwrapped.override {
      libplacebo = final.libplacebo-mpv;
    };
    libplacebo-mpv = prev.libplacebo.overrideAttrs (old: {
      src = prev.fetchFromGitLab {
        domain = "code.videolan.org";
        owner = "videolan";
        repo = "libplacebo";
        rev = "v7.349.0";
        hash = "sha256-mIjQvc7SRjE1Orb2BkHK+K1TcRQvzj2oUOCUT4DzIuA=";
      };
    });
    mpv = prev.mpv.override {
      scripts = with prev.mpvScripts; [
        mpv-webm
        mpris
        quality-menu
        sponsorblock-minimal
      ];
    };
    neovim = inputs.nixvim-config.packages.${prev.system}.default;
  };

  # Keep the stable overlay as is
  stable = final: _: {
    stable = inputs.nixpkgs-stable.legacyPackages.${final.system};
  };
}
