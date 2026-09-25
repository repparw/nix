{ den, lib, ... }:
{
  den = {
    schema.user.classes = lib.mkDefault [ "homeManager" ];

    schema.host.includes = [
      den.batteries.hostname
      den.aspects.networking
      den.aspects.secrets
      den.aspects.fleet-cli
    ];

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

      nixos.nix.settings.min-free = 3 * 1024 * 1024 * 1024;
      nixos.nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 21d";
      };
      nixos.boot.tmp.useTmpfs = true;

      nixos.sops.secrets."hermes-env".sopsFile = ../secrets/hermes.sops.yaml;
    };
  };
}
