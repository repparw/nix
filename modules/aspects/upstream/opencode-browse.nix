{
  den,
  inputs,
  ...
}:
{
  # Pin NixOS/nixpkgs#585097's expression to a commit so fresh CI fetches
  # still match the lockfile after the PR branch advances.
  flake-file.inputs.opencode-browse-pr = {
    url = "https://raw.githubusercontent.com/repparw/nixpkgs/dc035f952bdbaadadcb159d0b7362f8cb76a8bc9/pkgs/by-name/op/opencode-browse/package.nix";
    flake = false;
  };

  den.aspects.ai.provides.browse-desktop.provides.to-hosts.nixos.nixpkgs.overlays = [
    (final: _prev: {
      opencode-browse = final.callPackage inputs.opencode-browse-pr.outPath { };
    })
  ];
}
