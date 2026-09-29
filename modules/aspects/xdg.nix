{
  den,
  ...
}:
{
  den.aspects.xdg = {
    homeManager =
      { config, ... }:
      let
        inherit (config.xdg) cacheHome configHome dataHome stateHome;
      in
      {
        xdg.configFile."wget/wgetrc".text = ''
          hsts-file = ${dataHome}/wget-hsts
        '';

        home.sessionVariables = {
          NPM_CONFIG_CACHE = "${cacheHome}/npm";

          ANDROID_USER_HOME = "${dataHome}/android";

          WGETRC = "${configHome}/wget/wgetrc";

          HISTFILE = "${stateHome}/bash/history";
        };
      };
  };
}
