{ den, ... }:
{
  # Imported on Epsilon only. Nothing starts unless explicitly opted in.
  den.aspects.nixos-services.provides.event-bus.nixos =
    { config, lib, pkgs, ... }:
    let
      cfg = config.modules.fleet-event-bus;
    in
    {
      options.modules.fleet-event-bus.enable = lib.mkEnableOption ''
        staged, loopback-only NATS JetStream event transport (no producers
        or consumers migrated yet)
      '';

      config = lib.mkIf cfg.enable {
        services.nats = {
          enable = true;
          jetstream = true;
          serverName = "epsilon-fleet-events";
          port = 4222;
          # Keep the transport strictly local until SOPS-managed authentication,
          # per-producer/consumer permissions, and the cross-host transport are
          # reviewed together. In particular, never open 4222 to the WAN.
          settings = {
            host = "127.0.0.1";
            jetstream = {
              max_mem = "64M";
              max_file = "512M";
            };
          };
        };

        environment.systemPackages = [ pkgs.natscli ];
      };
    };
}
