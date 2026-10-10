{ ... }:
{
  den.aspects.glib-xdgmime-fix.nixos =
    { config, lib, ... }:
    let
      overlay = final: prev: {
        # Remove after the pinned GLib carries upstream ca75aff83af9875.
        glib =
          assert lib.assertMsg (
            prev.glib.version == "2.88.3"
          ) "Verify the GLib MIME parser fix before updating or retiring its security backport.";
          prev.glib.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [
              (final.fetchurl {
                url = "https://github.com/GNOME/glib/commit/ca75aff83af9875ea2ad2bfbe48a85dfd99c2ce5.patch";
                hash = "sha256-AMVQIu/59QmG228y/DWk8NraD6J5oYWQTkpPOrOOeGE=";
              })
            ];
          });
      };
      cfg = config.modules.services;
      containers = lib.filterAttrs (
        _: service: service.host == cfg.hostName && service.container
      ) cfg.definitions;
    in
    {
      nixpkgs.overlays = [ overlay ];
      containers = lib.mapAttrs (_: _: { config.nixpkgs.overlays = [ overlay ]; }) containers;
    };
}
