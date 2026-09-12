{
  lib,
  ...
}:
# Edge ingress stack: Traefik, Authelia, and ddclient. Its services publish
# their operational metadata through the fleet service registry.
{
  den.aspects.nixos-services.provides.edge = {
    service-registry = [
      {
        name = "authelia";
        definition = {
          hostname = "auth";
          port = 9091;
          auth = "bypass";
          container = true;
          monitor = true;
          healthcheck = "/api/health";
          backupRelativePath = "authelia";
        };
      }
      {
        name = "glance";
        definition = {
          port = 8080;
          auth = "bypass";
          container = true;
        };
      }
      {
        name = "miniflux";
        definition = {
          hostname = "rss";
          port = 8081;
          auth = "one_factor";
          container = true;
          monitor = true;
          healthcheck = "/healthcheck";
          backupRelativePath = "miniflux";
        };
      }
    ];

    nixos =
      { ... }:
      {
        imports = [
          ../../_services/proxy.nix
          ../../_services/authelia.nix
          ../../_services/ddclient.nix
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
