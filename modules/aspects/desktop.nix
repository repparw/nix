{
  den,
  inputs,
  ...
}:
{
  # The desktop user layer: window-manager-side tools and the desktop-only
  # AI tooling. Attach it to whichever user sits at a desktop host — it
  # injects the GUI host stack via to-hosts and configures the user's home.
  den.aspects.desktop = {
    includes = [
      den.aspects.phone
      den.aspects.editors
      den.aspects.file-manager
      den.aspects.scripts
      den.aspects.obsidian
      # GUI AI tooling (dictation/speech need input+sound hardware).
      den.aspects.ai._.gui
    ];

    provides.to-hosts = {
      includes = [ den.aspects.gui ];
      nixos.home-manager.sharedModules = [ inputs.nixcord.homeModules.default ];
    };
  };
}
