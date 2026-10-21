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
  scrapeBlock =
    name: text:
    builtins.head (
      lib.splitString "\n}" (builtins.elemAt (lib.splitString ''prometheus.scrape "${name}" {'' text) 1)
    );
  cloudFixture = signal: {
    url =
      if signal == "metrics" then
        "https://metrics.example.test/api/prom/push"
      else
        "https://logs.example.test/loki/api/v1/push";
    username = "fixture-${signal}";
    tokenFile = "/run/secrets/fixture-${signal}";
  };
  cloudConfig =
    signals:
    (inputs.self.nixosConfigurations.epsilon.extendModules {
      modules = [
        {
          modules.monitoring.agent.cloud = lib.genAttrs [ "metrics" "logs" ] (
            signal: if builtins.elem signal signals then cloudFixture signal else null
          );
        }
      ];
    }).config;
  cloudVariants = map cloudConfig [
    [ "metrics" ]
    [ "logs" ]
    [
      "metrics"
      "logs"
    ]
  ];
  redirectConfig = (cfg "epsilon").services.traefik.dynamicConfigOptions.http;
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
  cloudOnly =
    host:
    let
      config = cfg host;
      text = alloyConfig host;
    in
    config.services.alloy.enable
    && !config.services.prometheus.enable
    && !config.services.loki.enable
    && !config.services.grafana.enable
    && !(config.sops.secrets ? monitoring-agent-password)
    && !(config.sops.secrets ? monitoring-ingestion-users)
    && !(config.modules.services.definitions ? grafana)
    && !(lib.hasInfix "epsilon.receiver" text)
    && !(lib.hasInfix "ingestion-password" text)
    && lib.hasInfix ''prometheus.remote_write "cloud"'' text
    && lib.hasInfix ''loki.write "cloud"'' text
    && lib.hasInfix ''scrape_interval = "60s"'' (scrapeBlock "node_cloud" text)
    && lib.hasInfix ''scrape_interval = "60s"'' (scrapeBlock "alloy_cloud" text)
    && lib.hasInfix "prometheus.relabel.alloy.receiver" (scrapeBlock "alloy_cloud" text)
    && lib.hasInfix ''regex = ".*_bucket"'' text
    && lib.hasInfix "max_backoff_retries = 0" text
    &&
      lib.all
        (
          signal:
          builtins.elem "grafana-cloud-${signal}-token:/run/secrets/grafana-cloud-write-token" config.systemd.services.alloy.serviceConfig.LoadCredential
        )
        [
          "metrics"
          "logs"
        ];
  alphaExclusions =
    (cfg "alpha").modules.monitoring.agent.extraExcludedMounts == alphaMounts
    && lib.all (path: lib.hasInfix path (alloyConfig "alpha")) alphaMounts
    && lib.all (path: !(lib.hasInfix path (alloyConfig "pi"))) alphaMounts;
  glanceWidgets =
    lib.concatMap (column: column.widgets)
      (builtins.head (cfg "epsilon").containers.glance.config.services.glance.settings.pages).columns;
  glanceMonitor = lib.findFirst (widget: widget.type == "monitor") null glanceWidgets;
  cloudSite = lib.findFirst (site: site.title == "grafana") null glanceMonitor.sites;
in
assert lib.all cloudOnly hosts;
assert lib.all (port: !(builtins.elem port (cfg "epsilon").networking.firewall.allowedTCPPorts)) [
  9090
  3100
  3001
  12345
];
assert !(redirectConfig.routers ? grafana-local-health);
assert !(redirectConfig.routers ? monitoring-metrics);
assert !(redirectConfig.routers ? monitoring-logs);
assert !(redirectConfig.services ? grafana);
assert
  !(lib.hasInfix "authenticated Alloy ingestion" (cfg "epsilon").networking.firewall.extraInputRules);
assert redirectConfig.routers.grafana.service == "noop@internal";
assert redirectConfig.routers.grafana.middlewares == [ "grafana-cloud-redirect" ];
assert
  redirectConfig.middlewares.grafana-cloud-redirect.redirectRegex.replacement
  == "https://repparw.grafana.net\${1}";
assert !redirectConfig.middlewares.grafana-cloud-redirect.redirectRegex.permanent;
assert cloudSite.check-url == "https://repparw.grafana.net/api/health";
assert lib.all
  (
    path:
    lib.any (entry: entry.directory == path)
      (cfg "epsilon").environment.persistence."/persist".directories
  )
  [
    "/var/lib/grafana"
    "/var/lib/loki"
    "/var/lib/prometheus2"
  ];
assert alphaExclusions;
assert (cfg "epsilon").modules.disk-watch.enable;
assert (cfg "pi").systemd.timers ? fleet-health;
assert lib.all (
  variant:
  let
    text = variant.environment.etc."alloy/config.alloy".text;
  in
  lib.all
    (
      signal:
      if variant.modules.monitoring.agent.cloud.${signal} == null then
        !(lib.hasInfix "grafana-cloud-${signal}-token" text)
      else
        lib.hasInfix "/run/credentials/alloy.service/grafana-cloud-${signal}-token" text
    )
    [
      "metrics"
      "logs"
    ]
) cloudVariants;
pkgs.runCommand "check-monitoring-fleet"
  {
    nativeBuildInputs = [
      pkgs.grafana-alloy
      pkgs.prometheus.cli
    ];
  }
  ''
    ${lib.concatMapStringsSep "\n" (
      host:
      "alloy validate --stability.level=experimental ${pkgs.writeText "alloy-${host}.alloy" (alloyConfig host)}"
    ) hosts}
    ${lib.concatImapStringsSep "\n" (
      index: variant:
      "alloy validate --stability.level=experimental ${
        pkgs.writeText "alloy-cloud-${toString index}.alloy"
          variant.environment.etc."alloy/config.alloy".text
      }"
    ) cloudVariants}
    promtool test rules ${queryTests}
    touch $out
  ''
