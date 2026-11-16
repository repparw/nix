{
  den,
  inputs,
  ...
}:
{
  # Follow the moving package expression in NixOS/nixpkgs#585097's head
  # branch, but lock its contents through the normal flake update workflow.
  flake-file.inputs.opencode-browse-pr = {
    url = "https://raw.githubusercontent.com/repparw/nixpkgs/refs/heads/feat/opencode-browse-0.0.15/pkgs/by-name/op/opencode-browse/package.nix";
    flake = false;
  };

  den.aspects.ai.provides.browse-desktop.provides.to-hosts.nixos.nixpkgs.overlays = [
    (final: _prev: {
      opencode-browse = final.callPackage inputs.opencode-browse-pr.outPath { };
    })
  ];
}
