{ ... }:
{
  den.aspects.glib-xdgmime-fix.nixos = {
    nixpkgs.overlays = [
      (final: prev: {
        # Remove after the pinned GLib carries upstream ca75aff83af9875.
        glib = assert prev.glib.version == "2.88.3"; prev.glib.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            (final.fetchurl {
              url = "https://github.com/GNOME/glib/commit/ca75aff83af9875ea2ad2bfbe48a85dfd99c2ce5.patch";
              hash = "sha256-AMVQIu/59QmG228y/DWk8NraD6J5oYWQTkpPOrOOeGE=";
            })
          ];
        });
      })
    ];
  };
}
