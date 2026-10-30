{ inputs, pkgs, ... }:
let
  monitoring = (import ../aspects/monitoring.nix { den = null; }).den.aspects.monitoring.provides;
  health =
    (import ../aspects/monitoring-health.nix { den = null; }).den.aspects.monitoring.provides.health;
  password = pkgs.writeText "cloud-fixture-password" "vm-test-credential";
  users = pkgs.runCommand "cloud-fixture-users" { nativeBuildInputs = [ pkgs.mkpasswd ]; } ''
    hash=$(mkpasswd --method=bcrypt --rounds=4 --stdin < ${password})
    printf 'fixture:%s\n' "$hash" > "$out"
  '';
  tls = pkgs.runCommand "cloud-fixture-tls" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    mkdir "$out"
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -keyout "$out/key.pem" -out "$out/cert.pem" \
      -subj /CN=cloud.example.test -addext subjectAltName=DNS:cloud.example.test
  '';
in
pkgs.testers.runNixOSTest {
  name = "cloud-only-monitoring";
  nodes = {
    server = {
      imports = [ monitoring.dashboard.nixos ];
      options.modules.services = pkgs.lib.mkOption { type = pkgs.lib.types.attrs; };
      options.modules.monitoring.cloudUrl = pkgs.lib.mkOption { type = pkgs.lib.types.str; };
      # The production aspect keeps historical bind mounts; the fixture has no
      # impermanent root, so declare this unused option without enabling binds.
      options.environment.persistence = pkgs.lib.mkOption { type = pkgs.lib.types.attrs; };
      config = {
        modules.services.domain = "example.test";
        modules.monitoring.cloudUrl = "https://fixture.grafana.net";
        networking.interfaces.eth1.ipv4.addresses = pkgs.lib.mkForce [
          {
            address = "192.168.1.1";
            prefixLength = 24;
          }
        ];
        networking.firewall.allowedTCPPorts = [ 443 ];
        services.traefik = {
          enable = true;
          staticConfigOptions.entryPoints.websecure.address = "127.0.0.1:8443";
          dynamicConfigOptions.http.routers.grafana = {
            entryPoints = [ "websecure" ];
            tls = { };
          };
        };
        # Test-only HTTPS sink stands in for Grafana Cloud. Production hosts
        # have none of these receiver services or ports.
        services.prometheus = {
          enable = true;
          listenAddress = "127.0.0.1";
          extraFlags = [ "--web.enable-remote-write-receiver" ];
        };
        services.loki = {
          enable = true;
          configuration = {
            auth_enabled = false;
            server.http_listen_address = "127.0.0.1";
            common = {
              path_prefix = "/var/lib/loki";
              replication_factor = 1;
              ring = {
                instance_addr = "127.0.0.1";
                kvstore.store = "inmemory";
              };
            };
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
          };
        };
        services.nginx = {
          enable = true;
          virtualHosts."cloud.example.test" = {
            forceSSL = true;
            sslCertificate = "${tls}/cert.pem";
            sslCertificateKey = "${tls}/key.pem";
            basicAuthFile = users;
            locations."/healthz".extraConfig = "auth_basic off; return 200 'healthy';";
            locations."/login-only".extraConfig = "auth_basic off; return 302 /healthz;";
            locations."/api/prom/push".proxyPass = "http://127.0.0.1:9090/api/v1/write";
            locations."/loki/api/v1/push".proxyPass = "http://127.0.0.1:3100/loki/api/v1/push";
          };
        };
        virtualisation.memorySize = 2048;
        environment.systemPackages = [
          pkgs.curl
          pkgs.jq
        ];
        system.stateVersion = "26.05";
      };
    };
    client = { lib, ... }: {
      imports = [
        monitoring.agent.nixos
        monitoring.persist.nixos
        health.nixos
        (inputs.impermanence + "/nixos.nix")
      ];
      options.modules.services = lib.mkOption { type = lib.types.attrs; };
      options.modules.backup.exports = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
      options.modules.fleet-unit-state.snapshot = lib.mkOption { type = lib.types.package; };
      config = {
        modules.fleet-unit-state.snapshot = pkgs.writeShellScriptBin "fleet-unit-snapshot" "exit 0";
        modules.services = {
          domain = "example.test";
          definitions = lib.genAttrs [ "fixture" "logintrap" ] (name: {
            monitor = true;
            hostname = "cloud";
            port = 443;
            auth = "bypass";
            healthcheck = if name == "fixture" then "/healthz" else "/login-only";
          });
        };
        networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
          {
            address = "192.168.1.2";
            prefixLength = 24;
          }
        ];
        virtualisation.diskImage = null;
        virtualisation.emptyDiskImages = [ 1024 ];
        virtualisation.fileSystems."/persist" = {
          device = "/dev/disk/by-label/alloy-persist";
          fsType = "ext4";
          neededForBoot = true;
          noCheck = true;
        };
        boot.initrd.systemd.enable = true;
        boot.initrd.systemd.storePaths = [
          pkgs.e2fsprogs
          pkgs.util-linux
        ];
        boot.initrd.systemd.services.prepare-alloy-disk = {
          wantedBy = [ "initrd.target" ];
          requiredBy = [ "sysroot-persist.mount" ];
          before = [ "sysroot-persist.mount" ];
          after = [ "dev-vda.device" ];
          requires = [ "dev-vda.device" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig.Type = "oneshot";
          script = "if ! ${pkgs.util-linux}/bin/blkid /dev/vda; then ${pkgs.e2fsprogs}/bin/mkfs.ext4 -L alloy-persist /dev/vda; fi";
        };
        networking.hostName = "pi";
        networking.hosts."192.168.1.1" = [ "cloud.example.test" ];
        security.pki.certificateFiles = [ "${tls}/cert.pem" ];
        modules.monitoring.agent = {
          cloud = {
            metrics = {
              url = "https://cloud.example.test/api/prom/push";
              username = "fixture";
              tokenFile = toString password;
            };
            logs = {
              url = "https://cloud.example.test/loki/api/v1/push";
              username = "fixture";
              tokenFile = toString password;
            };
          };
          extraExcludedMounts = [ "/mnt/hdd" ];
        };
        services.journald.settings.Journal = {
          Storage = "volatile";
          ForwardToConsole = lib.mkForce false;
        };
        systemd.mounts = [
          {
            what = "tmpfs";
            where = "/mnt/hdd";
            type = "tmpfs";
            options = "size=1m";
          }
        ];
        systemd.automounts = [
          {
            where = "/mnt/hdd";
            wantedBy = [ "multi-user.target" ];
            automountConfig.TimeoutIdleSec = "2s";
          }
        ];
        environment.systemPackages = [ pkgs.curl ];
        virtualisation.memorySize = 1024;
        system.stateVersion = "26.05";
      };
    };
  };
  testScript = ''
    import json
    import secrets
    import shlex
    import time
    import urllib.parse

    def prom(expression):
        url = "http://127.0.0.1:9090/api/v1/query?" + urllib.parse.urlencode({"query": expression})
        return json.loads(server.succeed("curl -fsS " + shlex.quote(url)))["data"]["result"]

    def logs(marker):
        params = {"query": '{host="pi"} |= "' + marker + '"', "limit": 50, "start": str(time.time_ns() - 300_000_000_000), "end": str(time.time_ns())}
        url = "http://127.0.0.1:3100/loki/api/v1/query_range?" + urllib.parse.urlencode(params)
        result = json.loads(server.succeed("curl -fsS " + shlex.quote(url)))["data"]["result"]
        return [line for stream in result for _, line in stream["values"]]

    start_all()
    server.wait_for_unit("nginx.service")
    server.wait_for_unit("traefik.service")
    server.wait_until_succeeds("curl -fsS http://127.0.0.1:3100/ready")
    client.wait_for_unit("alloy.service")

    with subtest("Grafana vanity hostname redirects without a local process"):
        server.fail("systemctl is-active grafana.service")
        for hostname in ["grafana.example.test", "metrics.example.test"]:
            for path in ["/", "/d/fleet-overview?orgId=1&from=now-1h", "/api/health"]:
                url = "https://" + hostname + path
                output = server.succeed("curl -ksS --connect-to " + hostname + ":443:127.0.0.1:8443 -o /dev/null -w '%{http_code} %{redirect_url}' " + shlex.quote(url))
                assert output == "302 https://fixture.grafana.net" + path, output

    with subtest("Cloud HTTPS authentication, metrics, and redacted logs"):
        client.succeed("test $(curl -s -o /dev/null -w '%{http_code}' -X POST https://cloud.example.test/api/prom/push) = 401")
        client.succeed("printf 'monitoring_fixture_value 42\\n' > /var/lib/fleet-metrics/textfile/test.prom")
        client.succeed("systemctl start fleet-health-metrics.service || { journalctl -u fleet-health-metrics.service --no-pager; exit 1; }")
        try:
            retry(lambda _last: len(prom('node_uname_info{host="pi"}')) == 1, timeout_seconds=90)
        except Exception:
            print(client.succeed("journalctl -u alloy --no-pager -n 80"))
            print(server.succeed("journalctl -u nginx --no-pager -n 40; cat /var/log/nginx/error.log | tail -20"))
            raise
        retry(lambda _last: len(prom('up{job="alloy",host="pi"} == 1')) == 1, timeout_seconds=150)
        retry(lambda _last: len(prom('monitoring_fixture_value{host="pi"} == 42')) == 1, timeout_seconds=150)
        assert not prom('{job="alloy",__name__=~".*_bucket"}')
        assert prom('prometheus_remote_storage_samples_failed_total{host="pi"}')
        retry(lambda _last: len(prom('probe_success{service="fixture"} == 1')) == 1, timeout_seconds=150)
        retry(lambda _last: len(prom('probe_success{service="logintrap"} == 0')) == 1, timeout_seconds=150)
        retry(lambda _last: len(prom('fleet_health_collection_timestamp_seconds{collector="host"}')) == 1, timeout_seconds=150)
        assert prom('node_systemd_unit_state{state="active"}')
        assert not prom('node_systemd_unit_state{state=~"inactive|activating|deactivating"}')
        assert not prom('{service="fixture",__name__=~"probe_http_duration_seconds|probe_dns_lookup_time_seconds"}')
        marker = "cloud-redaction-" + secrets.token_hex(6)
        token = "ghp_" + secrets.token_hex(18)
        client.succeed("logger -t monitoring-fixture " + shlex.quote(marker + " " + token))
        retry(lambda _last: len(logs(marker)) > 0, timeout_seconds=90)
        assert all(token not in line for line in logs(marker))
        client.fail("systemctl is-active mnt-hdd.mount")
        client.succeed("test $(systemctl show mnt-hdd.mount -p ActiveEnterTimestampMonotonic --value) = 0")
        for unit in ["grafana", "prometheus", "loki"]:
            client.fail(f"systemctl is-active {unit}.service")
        for port in [3001, 9090, 3100]:
            assert not client.succeed(f"ss -H -ltn 'sport = :{port}'").strip()

    with subtest("Cloud outage buffers both signals and recovers without restarting Alloy"):
        server.succeed("systemctl stop nginx")
        outage = "cloud-outage-" + secrets.token_hex(6)
        client.succeed("logger -t monitoring-fixture " + shlex.quote(outage))
        client.succeed("printf 'monitoring_fixture_value 43\\n' > /var/lib/fleet-metrics/textfile/test.prom")
        # A nonempty queue may contain older samples. Wait a whole scrape
        # interval and prove the unique journal marker reached disk before
        # restoring the receiver.
        client.wait_until_succeeds("grep -aFl " + shlex.quote(outage.rsplit("-", 1)[1]) + " /var/lib/alloy/data-alloy/loki.write.cloud/wal/[0-9]* >/dev/null", timeout=90)
        client.sleep(65)
        client.wait_until_succeeds("curl -fsS http://127.0.0.1:12345/metrics | grep '^prometheus_remote_storage_samples_pending{' | grep -v ' 0$'", timeout=30)
        client.succeed("test -d /var/lib/alloy/data-alloy/prometheus.remote_write.cloud/wal")
        client.succeed("test -d /var/lib/alloy/data-alloy/loki.write.cloud/wal")
        client.succeed("test ! -e /var/lib/alloy/data-alloy/prometheus.remote_write.epsilon")
        server.succeed("systemctl start nginx")
        retry(lambda _last: len(logs(outage)) > 0, timeout_seconds=180)
        retry(lambda _last: len(prom('monitoring_fixture_value{host="pi"} == 43')) == 1, timeout_seconds=180)

    with subtest("agent state and uploaded telemetry survive a tmpfs-root reboot"):
        # File persistence does not establish lossless replay of unsent data.
        # The separate outage test verifies retries without restarting Alloy.
        client.succeed("touch /var/lib/alloy/persistence-canary")
        client.shutdown()
        client.start()
        client.wait_for_unit("alloy.service")
        client.succeed("test -e /var/lib/alloy/persistence-canary")
        client.succeed("findmnt -rn -M /var/lib/private/alloy")
        assert prom('max_over_time(monitoring_fixture_value{host="pi"}[10m]) == 43')
        retry(lambda _last: len(prom('timestamp(node_uname_info{host="pi"}) > time() - 60')) == 1, timeout_seconds=150)
        assert logs(marker)
        assert logs(outage)
  '';
}
