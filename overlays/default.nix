{ inputs, ... }:

{
  nixpkgs.overlays = [
    # `(final: prev: { xxx = prev.xxx.override { ... }; })`
    (final: prev: {
      neovim = inputs.nixvim-config.packages.${prev.stdenv.hostPlatform.system}.default;
    })

    (final: _prev: {
      stable = import inputs.nixpkgs-stable {
        system = final.system or (_prev.system or "x86_64-linux");
        config.allowUnfree = true;
      };
    })
  ];
}
