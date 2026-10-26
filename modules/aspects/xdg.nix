{
  den,
  ...
}:
{
  den.aspects.xdg = {
    homeManager =
      { config, ... }:
      let
        inherit (config.xdg)
          dataHome
          ;
      in
      {
        xdg.configFile."wget/wgetrc".text = ''
          hsts-file = ${dataHome}/wget-hsts
        '';
      };
  };
}
