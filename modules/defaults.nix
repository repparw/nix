{ den, lib, ... }:
{
  den = {
    schema.user.classes = lib.mkDefault [ "homeManager" ];

    # Opt in to Den v0.20's scoped user content semantics. Explicit
    # cross-scope providers below preserve intended host settings.
    migrations.user-host-content.acknowledged = true;

    schema.host.includes = [
      den.batteries.hostname
      den.batteries.mutual-provider
      den.aspects.networking
      den.aspects.secrets
      den.aspects.fleet-cli
      # Every host participates in fleet monitoring, deploy, and service discovery.
      den.aspects.monitoring._.cloud
      den.aspects.fleet-unit-state
      den.aspects.deploy-target
      den.aspects.service-host
    ];

    default = {
      includes = with den.aspects; [
        nix-index
        monitoring._.agent
        fleet-reboot
        nixvim
        nixpkgs
        cargo-system-libs
        nix
        system
      ];

      nixos.system.stateVersion = "26.05";
      # Upstream moved nspawn container autoStart to machines.target; a
      # plain host never activates it, so containers silently die on the
      # first switch after the bump. Pull it into the boot chain.
      nixos.systemd.targets.machines.wantedBy = [ "multi-user.target" ];
      homeManager.home.stateVersion = "26.05";

      nixos.nix.settings = {
        min-free = lib.mkDefault (3 * 1024 * 1024 * 1024);
        max-free = lib.mkDefault (6 * 1024 * 1024 * 1024);
      };
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
