{ pkgs, ... }:
let
  eventBus = (import ../aspects/services/nats-event-bus.nix { den = null; })
    .den.aspects.nixos-services.provides.event-bus.nixos;
in
pkgs.testers.runNixOSTest {
  name = "fleet-event-bus";
  nodes.server = { ... }: {
    imports = [ eventBus ];
    modules.fleet-event-bus.enable = true;
    virtualisation.memorySize = 1024;
    environment.systemPackages = [ pkgs.coreutils ];
    system.stateVersion = "26.05";
  };
  testScript = ''
    start_all()
    server.wait_for_unit("nats.service")
    server.wait_until_succeeds("nats --server nats://127.0.0.1:4222 stream ls")
    server.succeed("nats --server nats://127.0.0.1:4222 stream add FLEET_EVENTS --subjects 'fleet.>' --storage file --retention limits --defaults")
    server.succeed("nats --server nats://127.0.0.1:4222 consumer add FLEET_EVENTS discord-reader --pull --deliver all --ack explicit --defaults")
    server.succeed("nats --server nats://127.0.0.1:4222 consumer add FLEET_EVENTS hermes-reader --pull --deliver all --ack explicit --defaults")

    with subtest("one event reaches two independent durable consumers"):
        server.succeed("nats --server nats://127.0.0.1:4222 pub fleet.crash.alpha '{\"event_id\":\"fixture-1\"}'")
        discord = server.succeed("timeout 20 nats --server nats://127.0.0.1:4222 consumer next FLEET_EVENTS discord-reader --count 1 --ack")
        assert "fixture-1" in discord, discord
        # Restart before Hermes reads. A Core NATS subscription would lose it.
        server.succeed("systemctl restart nats.service")
        server.wait_for_unit("nats.service")
        hermes = server.succeed("timeout 20 nats --server nats://127.0.0.1:4222 consumer next FLEET_EVENTS hermes-reader --count 1 --ack")
        assert "fixture-1" in hermes, hermes

    with subtest("new events still reach both consumers"):
        server.succeed("nats --server nats://127.0.0.1:4222 pub fleet.deploy.pi '{\"event_id\":\"fixture-2\"}'")
        for consumer in ("discord-reader", "hermes-reader"):
            result = server.succeed(
                "timeout 20 nats --server nats://127.0.0.1:4222 consumer next FLEET_EVENTS " + consumer + " --count 1 --ack"
            )
            assert "fixture-2" in result, (consumer, result)

    with subtest("no externally reachable listener"):
        server.succeed("ss -lnt | grep -E '127\\.0\\.0\\.1:4222\\b'")
        server.fail("ss -lnt | grep -E '0\\.0\\.0\\.0:4222\\b'")
  '';
}
