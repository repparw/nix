{ den, ... }:
{
  den.aspects.spotifast = {
    homeManager =
      { pkgs, ... }:
      {
        # Native Spotify client (egui + librespot) replacing cliamp on Alpha.
        #
        # Installing the package is what makes the desktop integration
        # usable at all: the binary, its CLI (devices/transfer/play-uri/...),
        # the launcher entry and the `x-scheme-handler/spotify` entry only
        # reach the XDG search path once the package is in the profile.
        home.packages = [ pkgs.spotifast ];
      };
  };
}
