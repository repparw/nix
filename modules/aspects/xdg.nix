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
          cacheHome
          configHome
          dataHome
          stateHome
          ;
      in
      {
        xdg.configFile."wget/wgetrc".text = ''
          hsts-file = ${dataHome}/wget-hsts
        '';

        home.sessionVariables = {
          NPM_CONFIG_CACHE = "${cacheHome}/npm";

          ANDROID_USER_HOME = "${dataHome}/android";

          CARGO_HOME = "${dataHome}/cargo";

          CLAUDE_CONFIG_DIR = "${configHome}/claude";

          WGETRC = "${configHome}/wget/wgetrc";

          HISTFILE = "${stateHome}/bash/history";
        };
      };
  };
}
