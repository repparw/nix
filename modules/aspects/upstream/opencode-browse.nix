{ den, ... }:
let
  # NixOS/nixpkgs#585097 introduces opencode-browse. Use the reviewed
  # package expression from our immutable PR commit until it reaches the pin.
  browsePackage = builtins.fetchurl {
    url = "https://raw.githubusercontent.com/repparw/nixpkgs/d8b96228a98bbb98de1bae0da0a285317dfc010d/pkgs/by-name/op/opencode-browse/package.nix";
    sha256 = "d048bfd1db7546dd49f8e4c2fb072e74dc8fae04452e143e508d42c43b9cfb21";
  };
in
{
  den.aspects.ai.provides.browse-desktop.nixos.nixpkgs.overlays = [
    (final: _prev: {
      opencode-browse = final.callPackage browsePackage { };
    })
  ];
}
