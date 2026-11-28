{
  den,
  inputs,
  ...
}:
{
  den.aspects.desktop = {
    includes = [ den.aspects.gui ];

    nixos = {
      home-manager.sharedModules = [ inputs.nixcord.homeModules.default ];
      services.displayManager.autoLogin.enable = true;
    };

    provides.to-users = {
      includes = [
        den.aspects.gui
        den.aspects.file-manager
        den.aspects.obsidian
        den.aspects.spotifast
        den.aspects.ai._.gui
        den.aspects.ai._.t3code-connect-desktop
        den.aspects.ai._.browse-desktop
        den.aspects.desktop._.bitwarden
      ];

      user.extraGroups = [
        "render"
        "video"
      ];
    };
  };
}
