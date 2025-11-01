{ inputs, ... }:
{
  modifications = final: prev: {
    neovim = inputs.nixvim-config.packages.${prev.stdenv.hostPlatform.system}.default;
  };

  # Keep the stable overlay as is
  stable = final: _: {
    stable = inputs.nixpkgs-stable.legacyPackages.${final.stdenv.hostPlatform.system};
  };
}
