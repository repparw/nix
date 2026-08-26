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
        # Static addresses from hosts/alpha.nix and hosts/pi.nix.
        alphaAddress = "192.168.0.18";
        piAddress = "192.168.0.4";

        # alpha fronts the service containers through Traefik; names must
        # match the router rules in _services/ingress-policy.nix.
        alphaNames = [
          "repparw.com"
          "home.repparw.com"
          "code.repparw.com"
          "auth.repparw.com"
          "bazarr.repparw.com"
          "finance.repparw.com"
          "jellyfin.repparw.com"
          "rss.repparw.com"
          "paper.repparw.com"
          "prowlarr.repparw.com"
          "qbit.repparw.com"
          "radarr.repparw.com"
          "sonarr.repparw.com"
        ];

        piNames = [
          "hyperion.repparw.com"
          "pihole.repparw.com"
        ];

        rendered = ''
          # BEGIN nix lan-hosts (modules/aspects/lan-hosts.nix)
          ${alphaAddress} ${lib.concatStringsSep " " alphaNames}
          ${piAddress} ${lib.concatStringsSep " " piNames}
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
            ${alphaAddress} = alphaNames;
            ${piAddress} = piNames;
          };
        };
      };
  };
}
