{ den, ... }:
let
  inherit (den.lib.policy) pipe;
in
{
  den.quirks.service-registry.description = "Service-owned routing, monitoring, and backup metadata";

  den.policies.collect-service-registry =
    { ... }:
    [
      (pipe.from "service-registry" [
        (pipe.collectAll ({ host, ... }: true))
        pipe.withProvenance
      ])
    ];

  den.schema.host.includes = [ den.policies.collect-service-registry ];
}
