{
  den,
  ...
}:
{
  den.aspects.hyprland = {
    includes = [ ];

    nixos = { ... }: {
      imports = [
        ../../lib/nixos-modules/gui/hyprland.nix
      ];
    };

    homeManager = { pkgs, ... }: {
      imports = [
        ../../lib/hm-modules/gui/wm/hyprland.nix
      ];
    };
  };
}
