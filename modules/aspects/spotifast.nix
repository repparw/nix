{ den, ... }:
{
  den.aspects.spotifast = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.spotifast ];
      };
  };
}
