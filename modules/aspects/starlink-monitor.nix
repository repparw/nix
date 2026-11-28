{ den, ... }:
{
  # Read-only Starlink dish telemetry for the host that can reach the user
  # terminal (192.168.100.1:9200 over the bypass router). The exporter is the
  # upstream sparky8512/starlink-grpc-tools Prometheus front end: on every
  # Alloy scrape it issues read-only get_status/get_history gRPC calls and
  # renders metrics from the dish's own history buffer. No dish config is
  # touched, and raw 1 Hz history samples are never retained remotely: the
  # exported history stats are windowed summaries computed at scrape time.
  den.aspects.starlink-monitor = {
    # The exporter has no point without the Alloy agent that scrapes it and
    # forwards to Grafana Cloud.
    includes = [ den.aspects.monitoring._.agent ];

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.modules.starlink.monitor;
        exporter = pkgs.callPackage ../_packages/starlink-grpc-prometheus.nix { };

        # Explicit allowlist of what leaves the host: everything else is
        # dropped by the monitoring agent's budget relabel. GPS and location
        # fields are never collected (no "location" mode) and the identifying
        # starlink_info metric (dish id, hardware/software version) is not in
        # the allowlist. 43 series per scrape at 60s.
        metricAllowlist = [
          # Status: state as one-of-11 enum series (CONNECTED, DISH_UNREACHABLE,
          # ...); uptime resets on dish reboot.
          "starlink_status_state"
          "starlink_status_uptime_seconds"
          "starlink_status_pop_ping_latency_ms"
          "starlink_status_pop_ping_drop_rate"
          "starlink_status_downlink_throughput_bps"
          "starlink_status_uplink_throughput_bps"
          "starlink_status_fraction_obstructed"
          "starlink_status_currently_obstructed"
          "starlink_status_direction_azimuth"
          "starlink_status_direction_elevation"
          "starlink_status_alerts"
          # Alerts worth alerting on for a fixed outdoor dish; the aggregated
          # bitmask stays in status_alerts.
          "starlink_status_alert_thermal_throttle"
          "starlink_status_alert_thermal_shutdown"
          "starlink_status_alert_is_heating"
          "starlink_status_alert_power_supply_thermal_throttle"
          "starlink_status_alert_mast_not_near_vertical"
          "starlink_status_alert_slow_ethernet_speeds"
          # History stats: counters over the samples since the previous
          # successful scrape (first scrape: --samples window). Drop ratio is
          # total_ping_drop / samples; count_full_ping_drop counts fully
          # silent seconds. end_counter/samples expose window coverage.
          "starlink_ping_stats_samples"
          "starlink_ping_stats_end_counter"
          "starlink_ping_stats_total_ping_drop"
          "starlink_ping_stats_count_full_ping_drop"
          "starlink_usage_download_usage_bytes"
          "starlink_usage_upload_usage_bytes"
          "starlink_power_latest_power"
          "starlink_power_mean_power"
          "starlink_power_min_power"
          "starlink_power_max_power"
          "starlink_power_total_energy"
          # Fields unknown to the pinned exporter version (new firmware adds
          # alert names) arrive here with a metric=<field> label, bounded by
          # the firmware's field set. Extend the list above when they matter.
          "starlink_exporter_unprocessed_metrics"
          # Synthetic Alloy scrape health; without it a dead exporter would
          # just look like absent metrics.
          "up"
        ];
      in
      {
        options.modules.starlink.monitor = {
          dishTarget = lib.mkOption {
            type = lib.types.str;
            default = "192.168.100.1:9200";
            description = "host:port of the Starlink user terminal gRPC endpoint.";
          };
          listenPort = lib.mkOption {
            type = lib.types.port;
            default = 9877;
            description = "Localhost port the exporter listens on.";
          };
          windowSamples = lib.mkOption {
            type = lib.types.ints.between 1 900;
            default = 120;
            description = ''
              History samples (1 Hz) used for the first history-stats window
              after startup; later windows span the gap since the previous
              successful scrape. 900 is the dish's full history buffer.
            '';
          };
        };

        config = {
          modules.monitoring.agent.extraScrapes = [
            {
              name = "starlink";
              address = "127.0.0.1:${toString cfg.listenPort}";
              # Two gRPC calls (status + history), each capped at a 10s
              # deadline inside the exporter.
              scrapeTimeout = "30s";
              inherit metricAllowlist;
            }
          ];

          systemd.services.starlink-exporter = {
            description = "Starlink dish Prometheus exporter (read-only gRPC)";
            after = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];

            serviceConfig = {
              ExecStart = ''
                ${exporter}/bin/starlink-grpc-prometheus \
                  --address 127.0.0.1 \
                  --port ${toString cfg.listenPort} \
                  --target ${cfg.dishTarget} \
                  --samples ${toString cfg.windowSamples} \
                  status alert_detail ping_drop usage power
              '';
              DynamicUser = true;
              Restart = "on-failure";
              RestartSec = "15s";

              # Outbound access is limited to the dish; inbound is loopback.
              IPAddressAllow = [
                "127.0.0.0/8"
                "192.168.100.1"
              ];
              IPAddressDeny = [ "any" ];

              CapabilityBoundingSet = [ "" ];
              LockPersonality = true;
              MemoryDenyWriteExecute = true;
              NoNewPrivileges = true;
              PrivateDevices = true;
              PrivateTmp = true;
              ProcSubset = "pid";
              ProtectClock = true;
              ProtectControlGroups = true;
              ProtectHome = true;
              ProtectHostname = true;
              ProtectKernelLogs = true;
              ProtectKernelModules = true;
              ProtectKernelTunables = true;
              ProtectProc = "invisible";
              ProtectSystem = "strict";
              RestrictAddressFamilies = [
                "AF_INET"
                "AF_INET6"
                "AF_UNIX"
              ];
              RestrictNamespaces = true;
              RestrictRealtime = true;
              RestrictSUIDSGID = true;
              SystemCallArchitectures = "native";
              SystemCallFilter = [ "@system-service" ];
              UMask = "0077";
            };
          };
        };
      };
  };
}
