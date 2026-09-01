{
  lib,
  ...
}:
# Edge ingress stack: Traefik, Authelia, and ddclient plus the shared service
# definition schema and cross-host inventory. Composable on any host that
# fronts public traffic.
{
  den.aspects.nixos-services.provides.edge = {
    nixos =
      { ... }:
      {
        imports = [
          ../../_services/proxy.nix
          ../../_services/authelia.nix
          ../../_services/ddclient.nix
          ../../service-definitions.nix
          ../../_services/inventory.nix
          # The dashboard lives with the edge: apex routing is local and the
          # most-visited page stops depending on alpha being up.
          ../../_services/glance.nix
          # Miniflux + its PostgreSQL run natively here; traefik
          # reaches them over the nspawn bridge gateway.
          ../../_services/miniflux.nix
        ];
      };
  };
}
