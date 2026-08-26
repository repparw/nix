{ den, lib, ... }:
{
  den = {
    schema.user.classes = lib.mkDefault [ "homeManager" ];

    aspects.host-common = {
      includes = [
        den.batteries.hostname
        den.aspects.auto-upgrade
        den.aspects.audio
        den.aspects.networking
        den.aspects.secrets
        den.aspects.style
      ];
    };

    default = {
      includes = with den.aspects; [
        nix-index
        nixvim
        nixpkgs
        nix
        system
      ];

      nixos.system.stateVersion = "26.05";
      # Upstream moved nspawn container autoStart to machines.target; a
      # plain host never activates it, so containers silently die on the
      # first switch after the bump. Pull it into the boot chain.
      nixos.systemd.targets.machines.wantedBy = [ "multi-user.target" ];
      homeManager.home.stateVersion = "26.05";
    };
  };
}
