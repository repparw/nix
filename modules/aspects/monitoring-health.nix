{ den, ... }:
{
  den.aspects.monitoring.provides.health.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.modules.monitoring.health;
      servicesLib = import ../_services/lib.nix { inherit lib pkgs; };
      sites = servicesLib.monitorSites config.modules.services config;
      probeSites = lib.filter (
        site:
        if site.title == "paperless" then
          config.networking.hostName == "epsilon"
        else
          config.networking.hostName == "pi"
      ) sites;
      probes = lib.optionals (config.modules.monitoring.agent.cloud.metrics != null) (
        map (site: {
          name = site.title;
          address = site.check-url;
          module = if site ? alt-status-codes then "backend" else "healthy";
          service = site.title;
        }) probeSites
        ++ lib.optionals (config.networking.hostName == "pi") [
          {
            name = "homepage";
            address = "https://${config.modules.services.domain}/";
            module = "healthy";
            service = "homepage";
          }
          {
            name = "grafana-cloud";
            address = "${config.modules.monitoring.cloudUrl}/api/health";
            module = "healthy";
            service = "grafana-cloud";
          }
        ]
      );
      settings = pkgs.writeText "fleet-health-metrics.json" (
        builtins.toJSON {
          disks = cfg.disks;
          requiredUnits =
            map (name: "container@${name}.service") (
              lib.attrNames (lib.filterAttrs (_: container: container.autoStart) config.containers)
            )
            ++ lib.optional config.services.traefik.enable "traefik.service";
          exports = lib.attrNames config.modules.backup.exports;
          probes = map (probe: probe.service) probes;
          rebootCheck = config.networking.hostName == "alpha";
        }
      );
      collector = pkgs.writeShellApplication {
        name = "fleet-health-metrics";
        runtimeInputs = [
          pkgs.python3
          pkgs.systemd
          pkgs.btrfs-progs
          config.modules.fleet-unit-state.snapshot
        ];
        text = ''
          exec python3 ${../scripts/fleet-health-metrics.py} ${settings} "$@"
        '';
      };
      unit = disks: {
        description =
          if disks then
            "Export mounted filesystem health facts"
          else
            "Export fleet health facts for Grafana Cloud";
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe collector}${lib.optionalString disks " --disks"}";
          StateDirectory = "fleet-health-metrics";
          StateDirectoryMode = "0700";
          TimeoutStartSec = "90s";
          UMask = "0022";
        };
      };
    in
    {
      options.modules.monitoring.health.disks = lib.mkOption {
        default = [ ];
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              mount = lib.mkOption { type = lib.types.str; };
              warn = lib.mkOption { type = lib.types.ints.between 0 100; };
              crit = lib.mkOption { type = lib.types.ints.between 0 100; };
              sleeping = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
            };
          }
        );
        description = "Filesystem thresholds; unmounted sleeping media retain their last observed values without being accessed.";
      };
      config = {
        assertions = [
          {
            assertion = lib.all (disk: disk.warn < disk.crit) cfg.disks;
            message = "Monitoring disk warning thresholds must be below critical thresholds";
          }
        ];
        systemd.services.fleet-health-metrics = unit false;
        systemd.services.fleet-disk-metrics = unit true;
        systemd.timers.fleet-health-metrics = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "30s";
            OnUnitActiveSec = "60s";
          };
        };
        systemd.timers.fleet-disk-metrics = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "30s";
            OnUnitActiveSec = "15min";
          };
        };
        environment.etc."alloy/config.alloy".text = lib.mkAfter (
          lib.optionalString (probes != [ ]) ''
            prometheus.exporter.blackbox "services" {
              config = ${
                builtins.toJSON (
                  builtins.toJSON {
                    modules = {
                      healthy = {
                        prober = "http";
                        timeout = "6s";
                        http = {
                          follow_redirects = false;
                          valid_status_codes = [ 200 ];
                          preferred_ip_protocol = "ip4";
                        };
                      };
                      backend = {
                        prober = "http";
                        timeout = "6s";
                        http = {
                          follow_redirects = false;
                          valid_status_codes = [
                            200
                            301
                            302
                            303
                            307
                            308
                            401
                            403
                          ];
                          preferred_ip_protocol = "ip4";
                        };
                      };
                    };
                  }
                )
              }
              targets = [${
                lib.concatMapStringsSep "" (probe: ''
                  { name = ${builtins.toJSON probe.name}, address = ${builtins.toJSON probe.address}, module = ${builtins.toJSON probe.module}, service = ${builtins.toJSON probe.service} },
                '') probes
              }]
            }
            prometheus.scrape "service_health" {
              targets = prometheus.exporter.blackbox.services.targets
              forward_to = [prometheus.relabel.probe_budget.receiver]
              scrape_interval = "60s"
              scrape_timeout = "10s"
              job_name = "fleet-service-health"
            }
            prometheus.relabel "probe_budget" {
              forward_to = [prometheus.remote_write.cloud.receiver]
              rule {
                source_labels = ["__name__"]
                regex = "probe_success|probe_duration_seconds|probe_http_status_code|probe_ssl_earliest_cert_expiry|up"
                action = "keep"
              }
            }
          ''
        );
      };
    };
}
