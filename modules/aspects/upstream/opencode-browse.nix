{
  den,
  inputs,
  ...
}:
{
  den.aspects.ai.provides.browse-desktop.provides.to-hosts.nixos.nixpkgs.overlays = [
    (final: _prev: {
      opencode-browse = final.callPackage inputs.opencode-browse-pr.outPath { };
    })
  ];
}
