{
  den,
  ...
}:
{
  den.aspects.ai.provides.t3code-connect = {
    homeManager =
      {
        config,
        lib,
        osConfig,
        pkgs,
        ...
      }:
      let
        launcher = pkgs.writeShellScriptBin "t3code-desktop-connect" ''
          export CODEX_HOME=${lib.escapeShellArg config.home.sessionVariables.CODEX_HOME}
          exec ${lib.getExe' config.programs.t3code.package "t3code-desktop"} "$@"
        '';
      in
      {
        home.packages = [ launcher ];

        xdg.desktopEntries.t3code = lib.mkIf (osConfig.modules.desktop.enable or false) {
          name = "T3 Code (Alpha)";
          exec = "t3code-desktop-connect %U";
          icon = "t3code";
          settings.StartupWMClass = "t3code";
          categories = [ "Development" ];
          mimeType = [ "x-scheme-handler/t3code" ];
        };

        # Keep a user-local entry authoritative over stale desktop files left
        # by older installs. XDG menu lookup prefers this directory to the
        # Home Manager profile's share/applications directory.
        home.file.".local/share/applications/t3code.desktop" =
          lib.mkIf (osConfig.modules.desktop.enable or false)
            {
              source = "${config.home.path}/share/applications/t3code.desktop";
            };
      };
  };
}
