_: {
  den.aspects.nixpkgs = {
    nixos = _: {
      nixpkgs.config.allowUnfree = true;
    };
  };
}
