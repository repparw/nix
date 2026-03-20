{
  den,
  ...
}:
{
  den.aspects.jellyfin-mpv-shim = {
    includes = [ ];

    homeManager =
      { ... }:
      {
        services.jellyfin-mpv-shim.enable = false;
      };
  };
}
