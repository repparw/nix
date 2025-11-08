{ inputs, ... }:
{
  nixpkgs.overlays = [
    # Package modifications overlay
    (final: prev: {
      neovim = inputs.nixvim-config.packages.${prev.stdenv.hostPlatform.system}.default;

      # example = prev.example.overrideAttrs (oldAttrs: rec {
      # ...
      # });
    })

    # Stable packages overlay
    (final: _prev: {
      stable = import inputs.nixpkgs-stable {
        system = final.system;
        config.allowUnfree = true;
      };
    })
  ];
}
