{
  den,
  inputs,
  ...
}:
{
  den.aspects.desktop = {
    includes = [
      den.aspects.gui
      den.aspects.file-manager
      den.aspects.obsidian
      den.aspects.ai._.gui
    ];

    user = _: {
      extraGroups = [
        "render"
        "video"
      ];
    };

    provides.to-hosts =
      { user, ... }:
      {
        includes = [ den.aspects.gui ];
        nixos =
          { lib, ... }:
          {
            options.modules.desktop.enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              readOnly = true;
              description = "Whether this host includes the desktop aspect";
            };

            config = {
              home-manager.sharedModules = [ inputs.nixcord.homeModules.default ];
              services.displayManager.autoLogin.user = user.name;
            };
          };
      };
  };
}
