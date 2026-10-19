{
  inputs,
  lib,
  pkgs,
}:
let
  hosts = [
    "alpha"
    "pi"
    "epsilon"
  ];
  cfg = host: inputs.self.nixosConfigurations.${host}.config;
  alloyConfig = host: (cfg host).environment.etc."alloy/config.alloy".text;
  alphaMounts = [
    "/mnt/hdd"
    "/mnt/seagate"
    "/home/containers/media/hdd"
    "/home/containers/media/seagate"
  ];
  dashboard = builtins.fromJSON (builtins.readFile ../aspects/monitoring/fleet-overview.json);
  absentTargets = (lib.findFirst (panel: panel.id == 7) null dashboard.panels).targets;
  networkTargets = lib.filter (
    panel:
    builtins.elem panel.id [
      4
      5
    ]
  ) dashboard.panels;
  queryTests = pkgs.writeText "monitoring-dashboard-tests.json" (
    builtins.toJSON {
      evaluation_interval = "1m";
      tests =
        map
          (missing: {
            interval = "1m";
            input_series = map (host: {
              series = "node_uname_info{host=\"${host}\"}";
              values = "1+0x10";
            }) (lib.filter (host: host != missing) hosts);
            promql_expr_test = lib.imap0 (index: target: {
              expr = target.expr;
              eval_time = "6m";
              exp_samples = [
                {
                  labels = if builtins.elemAt hosts index == missing then "{host=\"${missing}\"}" else "{}";
                  value = if builtins.elemAt hosts index == missing then 1 else 0;
                }
              ];
            }) absentTargets;
          })
          [
            "none"
            "alpha"
            "pi"
            "epsilon"
          ]
        ++ [
          {
            interval = "1m";
            input_series =
              lib.concatMap
                (
                  direction:
                  map
                    (device: {
                      series = "node_network_${direction}_bytes_total{host=\"alpha\",device=\"${device}\"}";
                      values = if device == "enp6s0" then "0+60x10" else "0+6000x10";
                    })
                    [
                      "enp6s0"
                      "lo"
                      "veth-fixture"
                    ]
                )
                [
                  "receive"
                  "transmit"
                ];
            promql_expr_test = map (panel: {
              expr = (builtins.head panel.targets).expr;
              eval_time = "6m";
              exp_samples = [
                {
                  labels = "{host=\"alpha\"}";
                  value = 1;
                }
              ];
            }) networkTargets;
          }
        ];
    }
  );
  lokiConfiguration =
    (pkgs.formats.yaml { }).generate "fleet-loki.yaml"
      (cfg "epsilon").services.loki.configuration;
  allAgents = lib.all (host: (cfg host).services.alloy.enable) hosts;
  receiverTargets =
    (cfg "epsilon").modules.monitoring.agent.receiverHost == "127.0.0.1"
    &&
      lib.all
        (
          host:
          (cfg host).modules.monitoring.agent.receiverHost == (cfg host)
          .modules.services.hostAddresses.epsilon
        )
        [
          "alpha"
          "pi"
        ];
  centralizedServer =
    (cfg "epsilon").services.prometheus.enable
    && (cfg "epsilon").services.loki.enable
    && (cfg "epsilon").services.grafana.enable
    &&
      lib.all
        (
          host:
          !(cfg host).services.prometheus.enable
          && !(cfg host).services.loki.enable
          && !(cfg host).services.grafana.enable
        )
        [
          "alpha"
          "pi"
        ];
  cloudDisabledByDefault = lib.all (
    host:
    (cfg host).modules.monitoring.agent.cloud.metrics == null
    && (cfg host).modules.monitoring.agent.cloud.logs == null
    && !(lib.hasInfix "grafana-cloud" (alloyConfig host))
  ) hosts;
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
    && lib.any (
      entry: entry.mount == "/persist" && entry.warn == 70 && entry.crit == 85
    ) (cfg "epsilon").modules.disk-watch.mounts
    && (cfg "epsilon").modules.disk-watch.interval == "*:0/15"
    && (cfg "epsilon").systemd.timers ? disk-watch;
in
assert (cfg "epsilon").services.grafana.settings.server.http_addr == "127.0.0.1";
assert !(cfg "epsilon").services.grafana.openFirewall;
assert (cfg "epsilon").services.grafana.settings."auth.proxy".enabled;
assert (cfg "epsilon").services.grafana.settings."auth.proxy".header_name == "Remote-User";
assert (cfg "epsilon").services.grafana.settings."auth.proxy".whitelist == "127.0.0.1,::1";
assert (cfg "epsilon").services.grafana.settings.auth.disable_login_form;
assert lib.all (port: !(builtins.elem port (cfg "epsilon").networking.firewall.allowedTCPPorts)) [
  9090
  3100
  3001
  12345
];
assert lib.all
  (
    path:
    lib.any (
      entry: (if builtins.isString entry then entry else entry.directory) == path
    ) (cfg "epsilon").environment.persistence."/persist".directories
  )
  [
    "/var/lib/grafana"
    "/var/lib/loki"
    "/var/lib/prometheus2"
  ];
assert (cfg "epsilon").services.prometheus.listenAddress == "127.0.0.1";
assert (cfg "epsilon").services.prometheus.port == 9091;
assert (cfg "epsilon").services.loki.configuration.server.http_listen_address == "127.0.0.1";
assert (cfg "epsilon").services.loki.configuration.server.http_listen_port == 3101;
assert (cfg "epsilon").modules.monitoring.server.ingestionSources == [ "10.5.5.1" ];
assert (cfg "epsilon").modules.monitoring.agent.authentication == null;
assert lib.all
  (
    host:
    (cfg host).modules.monitoring.agent.authentication.username == host
    && lib.hasInfix "password_file" (alloyConfig host)
    &&
      (cfg host).systemd.services.alloy.serviceConfig.LoadCredential == [
        "ingestion-password:/run/secrets/monitoring-agent-password"
      ]
  )
  [
    "alpha"
    "pi"
  ];
assert
  (cfg "epsilon")
  .services.traefik.dynamicConfigOptions.http.middlewares.monitoring-auth.basicAuth.removeHeader;
assert allAgents;
assert receiverTargets;
assert centralizedServer;
assert selfTelemetry;
assert cloudDisabledByDefault;
assert (cfg "epsilon").modules.monitoring.server.cloudRedirectUrl == null;
assert (cfg "epsilon").services.traefik.dynamicConfigOptions.http.routers.grafana.middlewares == [ "authelia" ];
assert !(builtins.hasAttr "grafana-cloud-redirect" (cfg "epsilon").services.traefik.dynamicConfigOptions.http.middlewares);
assert alphaExclusions;
assert epsilonDiskWatch;
pkgs.runCommand "check-monitoring-fleet"
  {
    nativeBuildInputs = [
      pkgs.grafana-alloy
      pkgs.grafana-loki
      pkgs.prometheus.cli
    ];
  }
  ''
    ${lib.concatMapStringsSep "\n" (
      host:
      "alloy validate ${lib.escapeShellArgs (lib.filter (lib.hasPrefix "--stability.level=") (cfg host).services.alloy.extraFlags)} ${pkgs.writeText "alloy-${host}.alloy" (alloyConfig host)}"
    ) hosts}
    loki -verify-config -config.file=${lokiConfiguration}
    promtool test rules ${queryTests}
    touch $out
  ''
