{ inputs, ... }:

{
  nixpkgs.overlays = [
    # `(final: prev: { xxx = prev.xxx.override { ... }; })`
    (final: prev: {
      neovim = inputs.nixvim-config.packages.${prev.stdenv.hostPlatform.system}.default;
      cfait = final.callPackage ../pkgs/cfait { };
    })
  ];
}
