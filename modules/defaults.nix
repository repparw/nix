{ den, lib, ... }:
{
  den = {
    schema.user.classes = lib.mkDefault [ "homeManager" ];

    aspects.host-common = {
      includes = [
        den.batteries.hostname
        den.aspects.networking
        den.aspects.secrets
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

      # Disk headroom policy (pi ENOSPC'd a build at 6.2G free): the daemon
      # GCs when free space drops below min-free mid-build instead of dying,
      # and old generations expire weekly so retention stops creeping.
      # 10G on pi's 40G disk made EVERY large build dip below the threshold,
      # auto-GC deleting in-flight deps ("reference X is not a valid path",
      # builders dying mid-fetch). 3G still guards ENOSPC without thrashing.
      nixos.nix.settings.min-free = 3 * 1024 * 1024 * 1024;
      nixos.nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 21d";
      };
      nixos.boot.tmp.useTmpfs = true;

      # Fleet-ops Discord delivery (health probe, update reports, backups,
      # coredump watch) posts with the hermes bot token. The hermes aspect
      # only exists on epsilon, so the secret is declared fleet-wide;
      # epsilon's container uid-mapping override merges on top.
      nixos.sops.secrets."hermes-env".sopsFile = ../secrets/hermes.sops.yaml;
    };
  };
}
