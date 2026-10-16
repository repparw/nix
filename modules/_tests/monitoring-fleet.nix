{
  inputs,
  lib,
  pkgs,
}:
let
  hosts = [ "alpha" "pi" "epsilon" ];
  cfg = host: inputs.self.nixosConfigurations.${host}.config;
  alloyConfig = host: (cfg host).environment.etc."alloy/config.alloy".text;
  alphaMounts = [
    "/mnt/hdd"
    "/mnt/seagate"
    "/home/containers/media/hdd"
    "/home/containers/media/seagate"
  ];
  allAgents = lib.all (host: (cfg host).services.alloy.enable) hosts;
  receiverTargets =
    (cfg "epsilon").modules.monitoring.agent.receiverHost == "127.0.0.1"
    && lib.all (
      host:
      (cfg host).modules.monitoring.agent.receiverHost
      == (cfg host).modules.services.hostAddresses.epsilon
    ) [ "alpha" "pi" ];
  centralizedServer =
    (cfg "epsilon").services.prometheus.enable
    && (cfg "epsilon").services.loki.enable
    && (cfg "epsilon").services.grafana.enable
    && lib.all (
      host:
      !(cfg host).services.prometheus.enable
      && !(cfg host).services.loki.enable
      && !(cfg host).services.grafana.enable
    ) [ "alpha" "pi" ];
  selfTelemetry = lib.all (
    host:
    lib.hasInfix ''prometheus.scrape "alloy"'' (alloyConfig host)
    && lib.hasInfix ''"127.0.0.1:12345"'' (alloyConfig host)
    && lib.hasInfix ''prometheus.remote_write "epsilon"'' (alloyConfig host)
  ) hosts;
  alphaExclusions =
    (cfg "alpha").modules.monitoring.agent.extraExcludedMounts == alphaMounts
    && lib.all (path: lib.hasInfix path (alloyConfig "alpha")) alphaMounts
    && lib.all (path: !(lib.hasInfix path (alloyConfig "pi"))) alphaMounts;
  epsilonDiskWatch =
    (cfg "epsilon").modules.disk-watch.enable
    && lib.any (entry: entry.mount == "/persist") (cfg "epsilon").modules.disk-watch.mounts
    && (cfg "epsilon").systemd.timers ? disk-watch;
in
assert allAgents;
assert receiverTargets;
assert centralizedServer;
assert selfTelemetry;
assert alphaExclusions;
assert epsilonDiskWatch;
pkgs.runCommand "check-monitoring-fleet" { } ''
  touch $out
''
