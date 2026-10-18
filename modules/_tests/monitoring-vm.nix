{ inputs, pkgs }:
let
  monitoring = (import ../aspects/monitoring.nix { den = null; }).den.aspects.monitoring.provides;
  testPassword = pkgs.writeText "monitoring-test-password" "vm-test-credential";
  testUsers = pkgs.runCommand "monitoring-test-users" { nativeBuildInputs = [ pkgs.mkpasswd ]; } ''
    hash=$(mkpasswd --method=bcrypt --rounds=4 --stdin < ${testPassword})
    printf 'pi:%s\n' "$hash" > "$out"
  '';
  common = { lib, ... }: {
    imports = [ monitoring.agent.nixos ];
    options.modules.services = lib.mkOption { type = lib.types.attrs; };
    config = {
      modules.services = {
        domain = "example.test";
        hostAddresses = {
          epsilon = "10.5.5.3";
          pi = "10.5.5.1";
          alpha = "10.5.5.2";
        };
      };
      virtualisation.vlans = [
        1
        2
      ];
      networking.useDHCP = false;
      networking.interfaces.eth1.ipv4.addresses = lib.mkForce [ ];
      networking.interfaces.eth1.ipv6.addresses = lib.mkForce [ ];
      networking.interfaces.eth2.ipv4.addresses = lib.mkForce [ ];
      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
      ];
      system.stateVersion = "26.05";
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "fleet-monitoring";
  nodes = {
    server = { lib, ... }: {
      imports = [
        common
        monitoring.server.nixos
        (inputs.impermanence + "/nixos.nix")
      ];
      networking.hostName = "epsilon";
      networking.firewall.enable = true;
      environment.persistence."/persist".directories = [ "/var/lib/nixos" ];
      networking.bridges.wg-home.interfaces = [ "eth1" ];
      networking.interfaces.wg-home.ipv4.addresses = [
        {
          address = "10.5.5.3";
          prefixLength = 24;
        }
      ];
      networking.interfaces.eth2.ipv4.addresses = lib.mkForce [
        {
          address = "192.168.2.1";
          prefixLength = 24;
        }
      ];
      modules.monitoring.agent = {
        receiverHost = "127.0.0.1";
        metricsPort = 9091;
        logsPort = 3101;
      };
      modules.monitoring.server = {
        usersFile = toString testUsers;
        ingestionSources = [ "10.5.5.1" ];
      };
      virtualisation.memorySize = 4096;
      virtualisation.diskImage = null;
      virtualisation.emptyDiskImages = [ 4096 ];
      virtualisation.fileSystems."/persist" = {
        device = "/dev/disk/by-label/monitor-persist";
        fsType = "ext4";
        neededForBoot = true;
        noCheck = true;
      };
      boot.initrd.systemd.enable = true;
      boot.initrd.systemd.storePaths = [
        pkgs.e2fsprogs
        pkgs.util-linux
      ];
      boot.initrd.systemd.services.prepare-monitoring-disk = {
        wantedBy = [ "initrd.target" ];
        requiredBy = [ "sysroot-persist.mount" ];
        before = [ "sysroot-persist.mount" ];
        after = [ "dev-vda.device" ];
        requires = [ "dev-vda.device" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig.Type = "oneshot";
        script = ''
          if ! ${pkgs.util-linux}/bin/blkid /dev/vda; then
            ${pkgs.e2fsprogs}/bin/mkfs.ext4 -L monitor-persist /dev/vda
          fi
        '';
      };
    };
    client = { lib, ... }: {
      imports = [ common ];
      networking.hostName = "pi";
      modules.monitoring.agent.authentication = {
        username = "pi";
        passwordFile = toString testPassword;
      };
      networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
        {
          address = "10.5.5.1";
          prefixLength = 24;
        }
      ];
      networking.interfaces.eth2.ipv4.addresses = lib.mkForce [
        {
          address = "192.168.2.2";
          prefixLength = 24;
        }
      ];
      virtualisation.memorySize = 1024;
      virtualisation.diskImage = null;
      services.journald.settings.Journal = {
        Storage = "volatile";
        RuntimeMaxUse = "50M";
      };
      modules.monitoring.agent.extraExcludedMounts = [ "/mnt/hdd" ];
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
    };
  };
  testScript = ''
    import json
    import secrets
    import shlex
    import urllib.parse

    def prom(expression, timestamp=None):
        params = {"query": expression}
        if timestamp is not None:
            params["time"] = timestamp
        url = "http://127.0.0.1:9091/api/v1/query?" + urllib.parse.urlencode(params)
        return json.loads(server.succeed("curl -fsS --max-time 30 " + shlex.quote(url)))["data"]["result"]

    def logs(marker):
        params = {"query": '{host="pi"} |= "' + marker + '"', "limit": 50}
        url = "http://127.0.0.1:3101/loki/api/v1/query_range?" + urllib.parse.urlencode(params)
        values = json.loads(server.succeed("curl -fsS --max-time 30 " + shlex.quote(url)))["data"]["result"]
        return [line for stream in values for _, line in stream["values"]]

    start_all()
    server.wait_for_unit("prometheus.service")
    server.wait_for_unit("loki.service")
    server.wait_for_unit("grafana.service")
    client.wait_for_unit("alloy.service")
    server.wait_until_succeeds("curl -fsS http://127.0.0.1:3101/ready")
    server.wait_for_unit("traefik.service")
    server.wait_until_succeeds("curl -fsS -H 'Host: metrics.example.test' http://127.0.0.1:3001/api/health")
    server.wait_until_succeeds("curl -fsS http://127.0.0.1:12345/metrics")
    server.wait_until_succeeds("curl -fsS http://127.0.0.1:9091/-/ready")

    with subtest("receiver firewall and local admin endpoints"):
        for port in [3001, 12345, 9091, 3101]:
            listeners = server.succeed(f"ss -H -ltn 'sport = :{port}'")
            assert f"127.0.0.1:{port}" in listeners, listeners
        client.succeed("ip addr add 10.5.5.99/24 dev eth1")
        for port, path in [(9090, "/api/v1/write"), (3100, "/loki/api/v1/push")]:
            url = f"http://10.5.5.3:{port}{path}"
            client.wait_until_succeeds(f"test $(curl -s -o /dev/null -w '%{{http_code}}' -X POST {url}) = 401")
            client.succeed(f"test $(curl -s -o /dev/null -w '%{{http_code}}' -X POST --user pi:wrong {url}) = 401")
            client.succeed(f"test $(curl -s -o /dev/null -w '%{{http_code}}' --user pi:vm-test-credential {url}) = 404")
            client.fail(f"curl -sS -o /dev/null -X POST --connect-timeout 2 --max-time 3 http://192.168.2.1:{port}{path}")
            client.fail(f"curl -sS -o /dev/null -X POST --interface 10.5.5.99 --connect-timeout 2 --max-time 3 http://10.5.5.3:{port}{path}")
        for port, path in [(9090, "/api/v1/query?query=up"), (3100, "/loki/api/v1/query?query=up")]:
            client.succeed(f"test $(curl -s -o /dev/null -w '%{{http_code}}' --user pi:vm-test-credential 'http://10.5.5.3:{port}{path}') = 404")
        for port in [9091, 3101]:
            client.fail(f"curl -sS -o /dev/null --connect-timeout 2 --max-time 3 http://10.5.5.3:{port}/")
        client.fail("curl -sS -o /dev/null --connect-timeout 2 --max-time 3 http://10.5.5.3:3001/api/health")
        client.fail("curl -sS -o /dev/null --connect-timeout 2 --max-time 3 http://10.5.5.3:12345/metrics")

    with subtest("Grafana trusts the loopback identity proxy without a second login"):
        server.succeed("curl -fsS -H 'Host: metrics.example.test' -H 'Remote-User: fixture-admin' -H 'Remote-Name: Fixture Admin' -H 'Remote-Email: fixture@example.test' http://127.0.0.1:3001/api/user | jq -e '.login == \"fixture-admin\" and .name == \"Fixture Admin\" and .email == \"fixture@example.test\"'")
        server.succeed("curl -fsS -H 'Host: metrics.example.test' -H 'Remote-User: fixture-admin' http://127.0.0.1:3001/api/user/orgs | jq -e 'any(.[]; .role == \"Admin\")'")
        server.succeed("test $(curl -s -o /dev/null -w '%{http_code}' -H 'Host: metrics.example.test' http://127.0.0.1:3001/api/user) = 401")
        server.succeed("test $(curl -s -o /dev/null -w '%{http_code}' --interface 10.5.5.3 -H 'Host: metrics.example.test' -H 'Remote-User: spoofed' http://127.0.0.1:3001/api/user) = 401")

    with subtest("remote write, journal redaction, and datasource provisioning"):
        client.succeed("printf 'monitoring_fixture_value 42\\n' > /var/lib/fleet-metrics/textfile/test.prom")
        client.wait_until_succeeds("curl -fsS http://127.0.0.1:12345/metrics")
        retry(lambda _last: len(prom('node_uname_info{host="pi"}')) == 1, timeout_seconds=120)
        retry(lambda _last: len(prom('up{job="alloy",host="pi"} == 1')) == 1, timeout_seconds=120)
        retry(lambda _last: len(prom('monitoring_fixture_value{host="pi"} == 42')) == 1, timeout_seconds=120)
        timestamp = server.succeed("date +%s").strip()
        marker = "monitoring-journal-" + secrets.token_hex(6)
        fake_token = "ghp_" + secrets.token_hex(18)
        client.succeed("logger -t monitoring-fixture " + shlex.quote(marker + " " + fake_token))
        retry(lambda _last: len(logs(marker)) > 0, timeout_seconds=90)
        assert all(fake_token not in line for line in logs(marker))
        server.succeed("curl -fsS -H 'Host: metrics.example.test' --user \"admin:$(cat /var/lib/grafana/admin-password)\" http://127.0.0.1:3001/api/datasources | jq -e 'length == 2 and any(.[]; .uid == \"fleet-prom\") and any(.[]; .uid == \"fleet-loki\")'")
        client.fail("systemctl is-active mnt-hdd.mount")
        client.succeed("test $(systemctl show mnt-hdd.mount -p ActiveEnterTimestampMonotonic --value) = 0")

    with subtest("short Loki outage retries without losing the marker"):
        server.succeed("systemctl stop loki")
        outage_marker = "monitoring-outage-" + secrets.token_hex(6)
        client.succeed("logger -t monitoring-fixture " + shlex.quote(outage_marker))
        client.sleep(5)
        server.succeed("systemctl start loki")
        server.wait_until_succeeds("curl -fsS http://127.0.0.1:3101/ready")
        retry(lambda _last: len(logs(outage_marker)) > 0, timeout_seconds=120)
        retry(lambda _last: len(prom('loki_write_batch_retries_total{host="pi",job="alloy",exported_host="10.5.5.3:3100"} > 0')) == 1, timeout_seconds=120)

    with subtest("shipped volatile journal survives client reboot"):
        client.shutdown()
        client.start()
        client.wait_for_unit("alloy.service")
        assert logs(marker)
        client.succeed("! journalctl -t monitoring-fixture --no-pager | grep -F " + shlex.quote(marker))

    with subtest("server tmpfs reset preserves TSDB, Loki, and Grafana credentials"):
        credentials = server.succeed("sha256sum /var/lib/grafana/admin-password /var/lib/grafana/secret-key")
        server.succeed("touch /root/volatile-monitoring-marker")
        server.succeed("systemctl stop alloy")
        client.succeed("systemctl stop alloy")
        server.shutdown()
        server.start()
        server.wait_for_unit("grafana.service")
        server.wait_until_succeeds("curl -fsS http://127.0.0.1:9091/-/ready")
        server.wait_until_succeeds("curl -fsS http://127.0.0.1:3101/ready")
        server.fail("test -e /root/volatile-monitoring-marker")
        assert credentials == server.succeed("sha256sum /var/lib/grafana/admin-password /var/lib/grafana/secret-key")
        assert logs(marker)
        assert prom('monitoring_fixture_value{host="pi"}', timestamp)
  '';
}
