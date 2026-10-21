{ den, ... }:
{
  # Alloy collects host metrics and filtered journals for Grafana Cloud.
  den.aspects.monitoring.provides.agent.nixos =
    { config, lib, ... }:
    let
      cfg = config.modules.monitoring.agent;
      # The upstream Linux collector also ignores other pseudo filesystems
      # by fs type; the mount list is only for paths that can trigger probes.
      excludedMounts = [
        "/dev"
        "/proc"
        "/sys"
        "/run/credentials"
        "/var/lib/docker"
        "/var/lib/containers/storage"
      ]
      ++ cfg.extraExcludedMounts;
      cloudMetricsEnabled = cfg.cloud.metrics != null;
      cloudLogsEnabled = cfg.cloud.logs != null;
      cloudDestinationType = lib.types.submodule {
        options = {
          url = lib.mkOption {
            type = lib.types.str;
            description = "Full Grafana Cloud HTTPS ingestion URL.";
          };
          username = lib.mkOption {
            type = lib.types.str;
            description = "Grafana Cloud metrics or logs instance ID.";
          };
          tokenFile = lib.mkOption {
            type = lib.types.str;
            description = "Runtime path to a write-scoped Cloud access-policy token (never its value).";
          };
        };
      };
      excludedMountsRegex =
        "^(" + lib.concatStringsSep "|" (map lib.escapeRegex excludedMounts) + ")($|/)";
    in
    {
      options.modules.monitoring.cloudUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://repparw.grafana.net";
        description = "Grafana Cloud stack origin for the dashboard and independent reachability checks.";
      };
      options.modules.monitoring.agent = {
        cloud = {
          metrics = lib.mkOption {
            type = lib.types.nullOr cloudDestinationType;
            default = null;
            description = "Cloud metrics destination scraped every 60s.";
          };
          logs = lib.mkOption {
            type = lib.types.nullOr cloudDestinationType;
            default = null;
            description = "Cloud logs destination using the native secret redaction pipeline.";
          };
        };
        extraExcludedMounts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional literal filesystem mountpoints omitted from Alloy collection.";
        };
      };

      config = {
        assertions = [
          {
            assertion = cloudMetricsEnabled || cloudLogsEnabled;
            message = "The monitoring agent requires a Cloud metrics or logs destination";
          }
          {
            assertion =
              builtins.match "https://[A-Za-z0-9-]+[.]grafana[.]net/?" config.modules.monitoring.cloudUrl != null;
            message = "modules.monitoring.cloudUrl must be a Grafana Cloud HTTPS origin";
          }
        ]
        ++ lib.optional cloudMetricsEnabled {
          assertion = lib.hasPrefix "https://" cfg.cloud.metrics.url;
          message = "modules.monitoring.agent.cloud.metrics.url must use HTTPS";
        }
        ++ lib.optional cloudLogsEnabled {
          assertion = lib.hasPrefix "https://" cfg.cloud.logs.url;
          message = "modules.monitoring.agent.cloud.logs.url must use HTTPS";
        };
        services.alloy = {
          enable = true;
          extraFlags = [
            "--disable-reporting"
            "--stability.level=experimental"
          ];
        };

        environment.etc."alloy/config.alloy".text = ''
          // The same Alloy process collects node_exporter metrics. This
          // exporter is internal to Alloy, so no per-host metrics port is open.
          prometheus.exporter.unix "node" {
            enable_collectors = ["systemd"]

            systemd {
              enable_restarts = true
              start_time     = true
            }

            textfile {
              directory = "/var/lib/fleet-metrics/textfile"
            }

            filesystem {
              mount_points_exclude = "${excludedMountsRegex}"
            }
          }

          ${lib.optionalString cloudMetricsEnabled ''
            prometheus.scrape "node_cloud" {
              targets         = prometheus.exporter.unix.node.targets
              forward_to      = [prometheus.remote_write.cloud.receiver]
              job_name        = "node"
              scrape_interval = "60s"
            }

            prometheus.scrape "alloy_cloud" {
              targets         = [{ "__address__" = "127.0.0.1:12345", "host" = "${config.networking.hostName}" }]
              honor_labels    = false
              forward_to      = [prometheus.relabel.alloy.receiver]
              job_name        = "alloy"
              scrape_interval = "60s"
            }

            // Retain delivery counters, but omit internal histogram buckets.
            prometheus.relabel "alloy" {
              forward_to = [prometheus.remote_write.cloud.receiver]
              rule {
                source_labels = ["__name__"]
                regex = ".*_bucket"
                action = "drop"
              }
            }

            prometheus.remote_write "cloud" {
              external_labels = { host = "${config.networking.hostName}" }

              endpoint {
                url = ${builtins.toJSON cfg.cloud.metrics.url}
                basic_auth {
                  username = ${builtins.toJSON cfg.cloud.metrics.username}
                  password_file = "/run/credentials/alloy.service/grafana-cloud-metrics-token"
                }
              }
            }
          ''}

          // Journald metadata is internal until explicitly promoted to labels.
          // Keep labels low-cardinality (never PID, cursor, command line).
          loki.relabel "journal" {
            forward_to = []

            rule {
              source_labels = ["__journal__systemd_unit"]
              target_label  = "unit"
            }
            rule {
              source_labels = ["__journal_priority_keyword"]
              target_label  = "level"
            }
            rule {
              source_labels = ["__journal_syslog_identifier"]
              target_label  = "identifier"
            }
          }

          loki.source.journal "host" {
            forward_to    = [loki.secretfilter.journal.receiver]
            relabel_rules = loki.relabel.journal.rules
            labels        = { host = "${config.networking.hostName}", source = "journald" }
            max_age       = "12h"
          }

          // Redact common leaked credentials. This is best-effort, not
          // proof that arbitrary sensitive content cannot be collected.
          loki.secretfilter "journal" {
            forward_to    = [${lib.optionalString cloudLogsEnabled "loki.write.cloud.receiver"}]
            redact_percent = 100
          }

          ${lib.optionalString cloudLogsEnabled ''
            loki.write "cloud" {
              wal {
                enabled = true
              }
              endpoint {
                max_backoff_retries = 0
                url = ${builtins.toJSON cfg.cloud.logs.url}
                basic_auth {
                  username = ${builtins.toJSON cfg.cloud.logs.username}
                  password_file = "/run/credentials/alloy.service/grafana-cloud-logs-token"
                }
              }
            }
          ''}

        '';

        systemd.services.alloy.serviceConfig.LoadCredential =
          lib.optional cloudMetricsEnabled "grafana-cloud-metrics-token:${cfg.cloud.metrics.tokenFile}"
          ++ lib.optional cloudLogsEnabled "grafana-cloud-logs-token:${cfg.cloud.logs.tokenFile}";

        # Writers of future fleet-specific .prom gauges use this shared
        # directory, independent of the telemetry agent implementation.
        systemd.tmpfiles.rules = [
          "d /var/lib/fleet-metrics/textfile 0755 root root - -"
        ];
      };
    };

  den.aspects.monitoring.provides.persist.nixos = {
    environment.persistence."/persist".directories = [
      {
        directory = "/var/lib/private/alloy";
        mode = "0755";
      }
    ];

  };

  # Grafana Cloud write credential. Each host has its own token scoped to
  # metrics:write and logs:write, encrypted in the host-specific sops file.
  den.aspects.monitoring.provides.cloud.nixos = { config, lib, ... }: {
    sops.secrets.grafana-cloud-write-token = {
      sopsFile = ../../secrets + "/grafana-cloud-${config.networking.hostName}.sops.yaml";
      key = "token";
      restartUnits = [ "alloy.service" ];
    };
    modules.monitoring.agent.cloud.metrics = lib.mkDefault {
      url = "https://prometheus-prod-40-prod-sa-east-1.grafana.net/api/prom/push";
      username = "3689389";
      tokenFile = config.sops.secrets.grafana-cloud-write-token.path;
    };
    modules.monitoring.agent.cloud.logs = lib.mkDefault {
      url = "https://logs-prod-024.grafana.net/loki/api/v1/push";
      username = "1840359";
      tokenFile = config.sops.secrets.grafana-cloud-write-token.path;
    };
  };

  den.aspects.monitoring.provides.dashboard.nixos =
    { config, lib, ... }:
    let
      fqdn = "metrics.${config.modules.services.domain}";
      origin = lib.removeSuffix "/" config.modules.monitoring.cloudUrl;
    in
    {
      services.traefik.dynamicConfigOptions.http = {
        routers.grafana = {
          rule = "Host(`${fqdn}`)";
          service = "noop@internal";
          middlewares = [ "grafana-cloud-redirect" ];
        };
        middlewares.grafana-cloud-redirect.redirectRegex = {
          regex = "^https?://${lib.escapeRegex fqdn}([/?].*|$)";
          replacement = origin + "\${1}";
          permanent = false;
        };
      };

      # Keep the existing bind mounts and their ownership for rollback.
      # Removing the services must not discard Epsilon's historical data.
      environment.persistence."/persist".directories = [
        "/var/lib/grafana"
        "/var/lib/loki"
        "/var/lib/prometheus2"
      ];
    };
}
