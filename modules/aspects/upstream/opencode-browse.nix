{
  den,
  inputs,
  ...
}:
{
  # Pin the package expression from NixOS/nixpkgs#585097 so a branch update
  # cannot change the file behind the lock hash.
  flake-file.inputs.opencode-browse-pr = {
    url = "https://raw.githubusercontent.com/repparw/nixpkgs/55e2f197377de729a2fed0179ae4fa57781ae0bd/pkgs/by-name/op/opencode-browse/package.nix";
    flake = false;
  };

  den.aspects.ai.provides.browse-desktop.provides.to-hosts.nixos.nixpkgs.overlays = [
    (final: _prev: {
      opencode-browse = final.callPackage inputs.opencode-browse-pr.outPath { };
    })
  ];
}
