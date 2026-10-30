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
assert redirectConfig.routers.grafana.rule
  == "Host(`grafana.repparw.com`) || Host(`metrics.repparw.com`)";
assert redirectConfig.routers.grafana.middlewares == [ "grafana-cloud-redirect" ];
assert
  redirectConfig.middlewares.grafana-cloud-redirect.redirectRegex.replacement
  == "https://repparw.grafana.net\${1}";
assert !redirectConfig.middlewares.grafana-cloud-redirect.redirectRegex.permanent;
assert lib.hasInfix "grafana" redirectConfig.middlewares.grafana-cloud-redirect.redirectRegex.regex;
assert lib.hasInfix "metrics" redirectConfig.middlewares.grafana-cloud-redirect.redirectRegex.regex;
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
      pkgs.python3
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
    PYTHONDONTWRITEBYTECODE=1 python3 ${./fleet-health-metrics.py} ${../scripts/fleet-health-metrics.py}
    PYTHONDONTWRITEBYTECODE=1 python3 ${./grafana-cloud-backup.py} ${../scripts/grafana-cloud-backup.py}
    touch $out
  ''
