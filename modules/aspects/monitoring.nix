{ den, ... }:
{
  # Alloy replaces node_exporter: it scrapes its built-in Unix exporter
  # locally, sends samples to Prometheus, and ships journald to Loki.
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
      logsReceivers = lib.concatStringsSep ", " (
        [ "loki.write.epsilon.receiver" ] ++ lib.optional cloudLogsEnabled "loki.write.cloud.receiver"
      );
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
      basicAuth = lib.optionalString (cfg.authentication != null) ''
        basic_auth {
          username = ${builtins.toJSON cfg.authentication.username}
          password_file = "/run/credentials/alloy.service/ingestion-password"
        }
      '';
      excludedMountsRegex =
        "^(" + lib.concatStringsSep "|" (map lib.escapeRegex excludedMounts) + ")($|/)";
    in
    {
      options.modules.monitoring.agent = {
        receiverHost = lib.mkOption {
          type = lib.types.str;
          default = config.modules.services.hostAddresses.epsilon;
          description = "Private host/IP for Loki and Prometheus remote-write ingestion.";
        };
        metricsPort = lib.mkOption {
          type = lib.types.port;
          default = 9090;
        };
        logsPort = lib.mkOption {
          type = lib.types.port;
          default = 3100;
        };
        authentication = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.submodule {
              options = {
                username = lib.mkOption { type = lib.types.str; };
                passwordFile = lib.mkOption { type = lib.types.str; };
              };
            }
          );
          default = null;
          description = "Runtime credential for authenticated private ingestion.";
        };
        cloud = {
          metrics = lib.mkOption {
            type = lib.types.nullOr cloudDestinationType;
            default = null;
            description = "Optional independent Cloud metrics destination scraped every 60s; Epsilon stays at 30s.";
          };
          logs = lib.mkOption {
            type = lib.types.nullOr cloudDestinationType;
            default = null;
            description = "Optional independent Cloud logs mirror using the native secret redaction pipeline.";
          };
        };
        extraExcludedMounts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional literal filesystem mountpoints omitted from Alloy collection.";
        };
      };

      config = {
        assertions =
          lib.optional cloudMetricsEnabled {
            assertion = lib.hasPrefix "https://" cfg.cloud.metrics.url;
            message = "modules.monitoring.agent.cloud.metrics.url must use HTTPS";
          }
          ++ lib.optional cloudLogsEnabled {
            assertion = lib.hasPrefix "https://" cfg.cloud.logs.url;
            message = "modules.monitoring.agent.cloud.logs.url must use HTTPS";
          };
        # Ship the host's systemd journal to the central Loki instance.
        # Entries already sent persist on Epsilon across Pi reboots even
        # though the Pi journal remains volatile.
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

          prometheus.scrape "node" {
            targets         = prometheus.exporter.unix.node.targets
            forward_to      = [prometheus.remote_write.epsilon.receiver]
            job_name        = "node"
            scrape_interval = "30s"
          }

          // Alloy's own /metrics exposes local scrape, remote-write and
          // Loki pipeline counters. Scrape over loopback; no public agent API.
          prometheus.scrape "alloy" {
            targets         = [{ "__address__" = "127.0.0.1:12345", "host" = "${config.networking.hostName}" }]
            honor_labels    = false
            forward_to      = [prometheus.remote_write.epsilon.receiver]
            job_name        = "alloy"
            scrape_interval = "30s"
          }

          prometheus.remote_write "epsilon" {
            external_labels = { host = "${config.networking.hostName}" }

            endpoint {
              ${basicAuth}
              url = "http://${cfg.receiverHost}:${toString cfg.metricsPort}/api/v1/write"
            }
          }

          ${lib.optionalString cloudMetricsEnabled ''
            // Scrape Cloud separately to control its samples per minute
            // without reducing Epsilon's local collection frequency.
            prometheus.scrape "node_cloud" {
              targets         = prometheus.exporter.unix.node.targets
              forward_to      = [prometheus.remote_write.cloud.receiver]
              job_name        = "node"
              scrape_interval = "60s"
            }

            prometheus.scrape "alloy_cloud" {
              targets         = [{ "__address__" = "127.0.0.1:12345", "host" = "${config.networking.hostName}" }]
              honor_labels    = false
              forward_to      = [prometheus.remote_write.cloud.receiver]
              job_name        = "alloy"
              scrape_interval = "60s"
            }

            // A separate writer keeps a Cloud outage from replacing Epsilon's WAL.
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
            forward_to    = [${logsReceivers}]
            redact_percent = 100
          }

          ${lib.optionalString cloudLogsEnabled ''
            loki.write "cloud" {
              wal {
                enabled = true
              }
              endpoint {
                url = ${builtins.toJSON cfg.cloud.logs.url}
                basic_auth {
                  username = ${builtins.toJSON cfg.cloud.logs.username}
                  password_file = "/run/credentials/alloy.service/grafana-cloud-logs-token"
                }
              }
            }
          ''}

          loki.write "epsilon" {
            endpoint {
              url                 = "http://${cfg.receiverHost}:${toString cfg.logsPort}/loki/api/v1/push"
              ${basicAuth}
              max_backoff_retries = 0
            }
          }
        '';

        systemd.services.alloy.serviceConfig.LoadCredential =
          lib.optionals (cfg.authentication != null) [
            "ingestion-password:${cfg.authentication.passwordFile}"
          ]
          ++ lib.optional cloudMetricsEnabled "grafana-cloud-metrics-token:${cfg.cloud.metrics.tokenFile}"
          ++ lib.optional cloudLogsEnabled "grafana-cloud-logs-token:${cfg.cloud.logs.tokenFile}";

        # Writers of future fleet-specific .prom gauges use this shared
        # directory, independent of the telemetry agent implementation.
        systemd.tmpfiles.rules = [
          "d /var/lib/fleet-metrics/textfile 0755 root root - -"
        ];
      };
    };

  den.aspects.monitoring.provides.credentials.nixos = { config, ... }: {
    sops.secrets.monitoring-agent-password = {
      sopsFile = ../../secrets + "/monitoring-${config.networking.hostName}.sops.yaml";
      key = "password";
      restartUnits = [ "alloy.service" ];
    };
    modules.monitoring.agent.authentication = {
      username = config.networking.hostName;
      passwordFile = config.sops.secrets.monitoring-agent-password.path;
    };
  };

  den.aspects.monitoring.provides.server-credentials.nixos = { config, ... }: {
    sops.secrets.monitoring-ingestion-users = {
      sopsFile = ../../secrets/monitoring-server.sops.yaml;
      key = "htpasswd";
      owner = "traefik";
      restartUnits = [ "traefik.service" ];
    };
    modules.monitoring.server.usersFile = config.sops.secrets.monitoring-ingestion-users.path;
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

  # Epsilon is the independent collector: it remains online when the home
  # power or uplink is down. Service routing is generated by the existing
  # registry / Traefik / Authelia integration.
  den.aspects.monitoring.provides.server = {
    # Fleet default already includes the agent; Epsilon explicitly enables
    # only the centralized receiver/dashboard services here.
    service-registry = {
      name = "grafana";
      definition = {
        hostname = "metrics";
        port = 3001;
        auth = "one_factor";
        monitor = true;
        healthcheck = "/api/health";
      };
    };

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.modules.services;
        # The canonical URL remains local until explicit cutover. Once
        # redirected, keep an independent local Grafana health endpoint.
        cloudRedirectConfig = lib.mkIf (config.modules.monitoring.server.cloudRedirectUrl != null) (
          let
            origin = lib.removeSuffix "/" config.modules.monitoring.server.cloudRedirectUrl;
            fqdn = "metrics.${cfg.domain}";
          in
          {
            http.routers.grafana = {
              service = lib.mkForce "noop@internal";
              middlewares = lib.mkForce [ "grafana-cloud-redirect" ];
            };
            http.routers.grafana-local-health = {
              rule = "Host(`${fqdn}`) && Path(`/api/health`)";
              service = "grafana";
              priority = 100;
            };
            http.middlewares.grafana-cloud-redirect.redirectRegex = {
              regex = "^https?://${lib.escapeRegex fqdn}([/?].*|$)";
              replacement = origin + "\${1}";
              permanent = false;
            };
          }
        );
        dashboardDir = pkgs.runCommand "fleet-grafana-dashboards" { } ''
          mkdir -p "$out"
          cp ${./monitoring/fleet-overview.json} "$out/fleet-overview.json"
        '';
      in
      {
        options.modules.monitoring.server = {
          # Keep the existing Grafana route during the Cloud pilot.
          cloudRedirectUrl = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Grafana Cloud stack HTTPS origin for an opt-in metrics URL redirect.";
          };
          usersFile = lib.mkOption {
            type = lib.types.str;
            description = "Runtime htpasswd file with per-host ingestion credentials.";
          };
          ingestionSources = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "WireGuard source addresses observed at the receiver.";
          };
        };
        config = {

          assertions = lib.optional (config.modules.monitoring.server.cloudRedirectUrl != null) {
            assertion =
              builtins.match "https://[A-Za-z0-9-]+[.]grafana[.]net/?" config.modules.monitoring.server.cloudRedirectUrl
              != null;
            message = "modules.monitoring.server.cloudRedirectUrl must be a Grafana Cloud stack HTTPS origin";
          };

          services.prometheus = {
            enable = true;
            listenAddress = "127.0.0.1";
            port = 9091;
            stateDir = "prometheus2";
            retentionTime = "30d";
            extraFlags = [
              "--storage.tsdb.retention.size=3GB"
              "--web.enable-remote-write-receiver"
            ];
          };

          # Single-process Loki with local TSDB index and chunk storage.
          # Retention is time-based, not a hard size cap.
          services.loki = {
            enable = true;
            configuration = {
              auth_enabled = false; # Authentication is enforced by the ingestion proxy.
              server = {
                http_listen_address = "127.0.0.1";
                grpc_listen_address = "127.0.0.1";
                http_listen_port = 3101;
              };
              common = {
                path_prefix = "/var/lib/loki";
                ring = {
                  instance_addr = "127.0.0.1";
                  kvstore.store = "inmemory";
                };
                replication_factor = 1;
              };
              frontend.address = "127.0.0.1";
              schema_config.configs = [
                {
                  from = "2024-01-01";
                  store = "tsdb";
                  object_store = "filesystem";
                  schema = "v13";
                  index = {
                    prefix = "index_";
                    period = "24h";
                  };
                }
              ];
              storage_config.filesystem.directory = "/var/lib/loki/chunks";
              limits_config = {
                retention_period = "168h"; # 7 days
                max_query_lookback = "168h";
              };
              compactor = {
                working_directory = "/var/lib/loki/compactor";
                retention_enabled = true;
                delete_request_store = "filesystem";
              };
            };
          };

          services.traefik = {
            enable = true;
            staticConfigOptions.entryPoints = {
              monitoring-metrics.address = ":9090";
              monitoring-logs.address = ":3100";
            };
            dynamicConfigOptions = lib.mkMerge [
              {
                http = {
                  middlewares.monitoring-auth.basicAuth = {
                    usersFile = config.modules.monitoring.server.usersFile;
                    removeHeader = true;
                  };
                  routers = {
                    monitoring-metrics = {
                      entryPoints = [ "monitoring-metrics" ];
                      rule = "Method(`POST`) && Path(`/api/v1/write`)";
                      middlewares = [ "monitoring-auth" ];
                      service = "monitoring-metrics";
                    };
                    monitoring-logs = {
                      entryPoints = [ "monitoring-logs" ];
                      rule = "Method(`POST`) && Path(`/loki/api/v1/push`)";
                      middlewares = [ "monitoring-auth" ];
                      service = "monitoring-logs";
                    };
                  };
                  services = {
                    monitoring-metrics.loadBalancer.servers = [ { url = "http://127.0.0.1:9091"; } ];
                    monitoring-logs.loadBalancer.servers = [ { url = "http://127.0.0.1:3101"; } ];
                  };
                };
              }
              cloudRedirectConfig
            ];
          };

          networking.nftables.enable = true;
          networking.firewall.extraInputRules = ''
            iifname "wg-home" ip saddr { ${lib.concatStringsSep ", " config.modules.monitoring.server.ingestionSources} } tcp dport { 9090, 3100 } accept comment "authenticated Alloy ingestion"
          '';

          services.grafana = {
            enable = true;
            openFirewall = false;
            settings = {
              server = {
                http_port = 3001;
                domain = "metrics.${cfg.domain}";
                root_url = "https://metrics.${cfg.domain}/";
                enforce_domain = true;
              };
              auth.disable_login_form = true;
              "auth.proxy" = {
                enabled = true;
                header_name = "Remote-User";
                header_property = "username";
                auto_sign_up = true;
                whitelist = "127.0.0.1,::1";
                headers = "Name:Remote-Name Email:Remote-Email";
                enable_login_token = false;
              };
              users = {
                allow_sign_up = false;
                auto_assign_org_role = "Admin";
              };
              security = {
                # File provider keeps the password out of the Nix store. The
                # first-start secret is generated below and persisted on disk.
                admin_password = "$__file{/var/lib/grafana/admin-password}";
                secret_key = "$__file{/var/lib/grafana/secret-key}";
                cookie_secure = true;
                disable_gravatar = true;
              };
            };
            provision = {
              enable = true;
              datasources.settings = {
                apiVersion = 1;
                datasources = [
                  {
                    name = "Prometheus";
                    type = "prometheus";
                    access = "proxy";
                    url = "http://127.0.0.1:9091";
                    uid = "fleet-prom";
                    isDefault = true;
                    editable = false;
                  }
                  {
                    name = "Loki";
                    type = "loki";
                    access = "proxy";
                    url = "http://127.0.0.1:3101";
                    uid = "fleet-loki";
                    isDefault = false;
                    editable = false;
                  }
                ];
              };
              dashboards.settings = {
                apiVersion = 1;
                providers = [
                  {
                    name = "Fleet";
                    type = "file";
                    disableDeletion = true;
                    editable = false;
                    options.path = dashboardDir;
                  }
                ];
              };
            };
          };

          systemd.services.grafana.preStart = lib.mkBefore ''
            # These values MUST remain stable when Epsilon reboots. Grafana's
            # secret key encrypts stored datasource and session secrets.
            umask 077
            if [ ! -s /var/lib/grafana/admin-password ]; then
              ${pkgs.coreutils}/bin/head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/base64 -w0 > /var/lib/grafana/admin-password
            fi
            if [ ! -s /var/lib/grafana/secret-key ]; then
              ${pkgs.coreutils}/bin/head -c 48 /dev/urandom | ${pkgs.coreutils}/bin/base64 -w0 > /var/lib/grafana/secret-key
            fi
          '';

          # Epsilon has a tmpfs root. Without these binds Grafana's SQLite DB,
          # first-start credentials and all Prometheus metrics vanish on reboot.
          environment.persistence."/persist".directories = [
            {
              directory = "/var/lib/grafana";
              user = "grafana";
              group = "grafana";
              mode = "0750";
            }
            {
              directory = "/var/lib/loki";
              user = "loki";
              group = "loki";
              mode = "0750";
            }
            {
              directory = "/var/lib/prometheus2";
              user = "prometheus";
              group = "prometheus";
              mode = "0750";
            }
          ];
        };
      };
  };
}
