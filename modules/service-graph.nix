{ den, ... }:
let
  inherit (den.lib.policy) pipe;
in
{
  den.quirks.service-registry.description = "Service-owned routing, monitoring, and backup metadata";

  den.policies.broadcast-service-registry =
    { host, ... }:
    [
      (pipe.from "service-registry" [
        (pipe.transform (service: service // { host = host.name; }))
        (pipe.broadcast ({ host, ... }: true))
      ])
    ];

  den.schema.host.includes = [ den.policies.broadcast-service-registry ];
}
