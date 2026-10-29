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
  persistencePaths = map (entry: if builtins.isAttrs entry then entry.directory else entry) (
    (cfg "epsilon").environment.persistence."/persist".directories
  );
  alphaMounts = [
    "/mnt/hdd"
    "/mnt/seagate"
    "/home/containers/media/hdd"
    "/home/containers/media/seagate"
  ];
  dashboard =
    (builtins.fromJSON (builtins.readFile ../../grafana/dashboards/fleet-overview.json)).spec;
  cpuTarget = builtins.head (lib.findFirst (panel: panel.id == 1) null dashboard.panels).targets;
  filesystemTarget =
    builtins.head
      (lib.findFirst (panel: panel.id == 3) null dashboard.panels).targets;
  failuresTarget = builtins.head (lib.findFirst (panel: panel.id == 6) null dashboard.panels).targets;
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
      fuzzy_compare = true;
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
                  labels = "{host=\"${builtins.elemAt hosts index}\"}";
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
            input_series = [
              {
                series = "node_uname_info{host=\"alpha\"}";
                values = "1+0x3 stale";
              }
            ];
            promql_expr_test =
              map
                (minute: {
                  expr = (builtins.head absentTargets).expr;
                  eval_time = "${toString minute}m";
                  exp_samples = [
                    {
                      labels = "{host=\"alpha\"}";
                      value = if minute == 4 then 0 else 1;
                    }
                  ];
                })
                [
                  4
                  10
                ];
          }
          {
            interval = "1m";
            input_series =
              lib.concatMap
                (
                  fixture:
                  map
                    (mode: {
                      series = "node_cpu_seconds_total{host=\"${fixture.host}\",cpu=\"0\",job=\"integrations/unix\",mode=\"${mode}\"}";
                      values = "0+${toString fixture.${mode}}x10";
                    })
                    [
                      "user"
                      "idle"
                    ]
                )
                [
                  {
                    host = "pi";
                    user = 1;
                    idle = 65;
                  }
                  {
                    host = "alpha";
                    user = 30;
                    idle = 30;
                  }
                  {
                    host = "epsilon";
                    user = 0;
                    idle = 60;
                  }
                  {
                    host = "saturated";
                    user = 60;
                    idle = 0;
                  }
                ]
              ++ [
                {
                  series = "node_cpu_seconds_total{host=\"pi\",cpu=\"0\",job=\"unrelated\",mode=\"user\"}";
                  values = "0+6000x10";
                }
              ];
            promql_expr_test = [
              {
                expr = cpuTarget.expr;
                eval_time = "6m";
                exp_samples = [
                  {
                    labels = "{host=\"pi\"}";
                    value = 100.0 / 66.0;
                  }
                  {
                    labels = "{host=\"alpha\"}";
                    value = 50;
                  }
                  {
                    labels = "{host=\"epsilon\"}";
                    value = 0;
                  }
                  {
                    labels = "{host=\"saturated\"}";
                    value = 100;
                  }
                ];
              }
            ];
          }
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
                      "ifb-wan"
                      "wg-home"
                      "br0"
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
          {
            interval = "1m";
            input_series =
              lib.concatMap
                (
                  mount:
                  map
                    (metric: {
                      series = "node_filesystem_${metric}_bytes{host=\"epsilon\",device=\"/dev/sda1\",fstype=\"ext4\",mountpoint=\"${mount}\"}";
                      values =
                        if metric == "size" then
                          "1000+0x10"
                        else if metric == "free" then
                          "500+0x10"
                        else
                          "450+0x10";
                    })
                    [
                      "size"
                      "free"
                      "avail"
                    ]
                )
                [
                  "/persist"
                  "/nix"
                  "/home/repparw"
                ];
            promql_expr_test = [
              {
                expr = filesystemTarget.expr;
                eval_time = "6m";
                exp_samples = [
                  {
                    labels = "{host=\"epsilon\",device=\"/dev/sda1\"}";
                    value = 100 * 500.0 / 950.0;
                  }
                ];
              }
            ];
          }
          {
            interval = "1m";
            input_series = [
              {
                series = "fleet_failed_unit{host=\"alpha\",name=\"first.service\"}";
                values = "1+0x10";
              }
              {
                series = "fleet_failed_unit{host=\"alpha\",name=\"second.service\"}";
                values = "1+0x10";
              }
              {
                series = "fleet_health_collection_timestamp_seconds{host=\"alpha\",collector=\"host\"}";
                values = "100+0x10";
              }
              {
                series = "fleet_health_collection_timestamp_seconds{host=\"epsilon\",collector=\"host\"}";
                values = "100+0x10";
              }
              {
                series = "fleet_failed_units{host=\"legacy\",job=\"integrations/unix\"}";
                values = "2+0x10";
              }
              {
                series = "node_systemd_unit_state{host=\"alpha\",name=\"test.service\",state=\"failed\"}";
                values = "0+0x10";
              }
              {
                series = "node_systemd_unit_state{host=\"pi\",name=\"test.service\",state=\"failed\"}";
                values = "1+0x10";
              }
            ];
            promql_expr_test = [
              {
                expr = failuresTarget.expr;
                eval_time = "6m";
                exp_samples = [
                  {
                    labels = "{host=\"alpha\"}";
                    value = 2;
                  }
                  {
                    labels = "{host=\"pi\"}";
                    value = 1;
                  }
                  {
                    labels = "{host=\"epsilon\"}";
                    value = 0;
                  }
                  {
                    labels = "{host=\"legacy\"}";
                    value = 2;
                  }
                ];
              }
            ];
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
assert !(lib.hasInfix ''name = "paperless"'' (alloyConfig "pi"));
assert lib.hasInfix
  ''{ name = "paperless", address = "http://${(cfg "epsilon").containers.paperless.localAddress}:8000"''
  (alloyConfig "epsilon");
assert (cfg "epsilon").containers.paperless.forwardPorts == [ ];
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
assert lib.all (path: !(builtins.elem path persistencePaths))
  [
    "/var/lib/grafana"
    "/var/lib/loki"
    "/var/lib/prometheus2"
  ];
assert alphaExclusions;
assert lib.all (host: !(cfg host).systemd.timers ? fleet-health) hosts;
assert lib.all (host: !(cfg host).systemd.timers ? disk-watch) hosts;
assert lib.all (host: !(cfg host).systemd.timers ? reboot-watch) hosts;
assert !((cfg "pi").systemd.services ? fleet-health-event);
assert map (disk: disk.mount) (cfg "epsilon").modules.monitoring.health.disks == [ "/persist" ];
assert lib.all (host: (cfg host).systemd.timers ? fleet-health-metrics) hosts;
assert lib.all (
  host: lib.hasInfix "node_systemd_unit_state;(inactive|activating|deactivating)" (alloyConfig host)
) hosts;
assert
  (lib.findFirst (disk: disk.mount == "/persist") null
    (cfg "epsilon").modules.monitoring.health.disks
  ).crit == 85;
assert
  (lib.findFirst (disk: disk.mount == "/mnt/hdd") null (cfg "alpha").modules.monitoring.health.disks)
  .sleeping;
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
      pkgs.python3
      pkgs.go
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
    GOCACHE="$TMPDIR/go-cache" GO111MODULE=off go run ${./discord-template.go} ${./fixtures/monitoring/discord.tmpl}
    PYTHONDONTWRITEBYTECODE=1 python3 ${./fleet-health-metrics.py} ${../scripts/fleet-health-metrics.py} ${./fixtures/monitoring/health-alerts.json}
    PYTHONDONTWRITEBYTECODE=1 python3 ${./grafana-cloud-backup.py} ${../scripts/grafana-cloud-backup.py}
    touch $out
  ''
