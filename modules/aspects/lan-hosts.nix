_: {
  # Canonical *.repparw.com -> LAN address mapping. Single source of truth for
  # everything that resolves these names locally:
  #
  #   - hosts including this aspect answer from networking.hosts (alpha, pi)
  #   - scripts/deploy-tv-hosts.sh pushes the rendered fragment onto the
  #     rooted webOS TV, which bind-mounts it over /etc/hosts at boot
  #
  # Kept static on purpose: the service definitions behind some of these
  # names live inside alpha's config and are invisible to other hosts, so
  # deriving the map there would silently produce an empty/partial list.
  # When adding a service, mirror its ingress-policy.nix router rule here.
  den.aspects.lan-hosts = {
    nixos =
      { lib, pkgs, ... }:
      let
        # Static address of the edge host (see hosts/pi.nix).
        piAddress = "192.168.0.4";
        # Phase 2 edge: epsilon fronts the apex; names move here as their
        # backends migrate off pi.
        epsilonAddress = "146.181.42.97";

        # Still routed by pi's traefik; names must match the router rules
        # in _services/ingress-policy.nix.
        piNames = [
          "auth.repparw.com"
          "bazarr.repparw.com"
          "finance.repparw.com"
          "home.repparw.com"
          "jellyfin.repparw.com"
          "paper.repparw.com"
          "prowlarr.repparw.com"
          "qbit.repparw.com"
          "radarr.repparw.com"
          "rss.repparw.com"
          "sonarr.repparw.com"
        ];

        # Served by epsilon directly (glance migration).
        epsilonNames = [
          "repparw.com"
        ];

        rendered = ''
          # BEGIN nix lan-hosts (modules/aspects/lan-hosts.nix)
          ${piAddress} ${lib.concatStringsSep " " piNames}
          ${epsilonAddress} ${lib.concatStringsSep " " epsilonNames}
          # END nix lan-hosts
        '';
      in
      {
        options.modules.lan-hosts.file = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "Rendered hosts fragment for external consumers (TV deployment).";
        };

        config = {
          modules.lan-hosts.file = pkgs.writeText "lan-hosts" rendered;

          networking.hosts = {
            ${piAddress} = piNames;
            ${epsilonAddress} = epsilonNames;
          };
        };
      };
  };
}
