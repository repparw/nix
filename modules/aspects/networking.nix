_:
{
  den.aspects.networking = {
    includes = [ ];

    nixos =
      { pkgs, lib, ... }:
      {
        networking.nftables.tables.qos = {
          family = "inet";
          content = ''
            chain postrouting {
              type filter hook postrouting priority mangle; policy accept;

              # Deprioritize qBittorrent traffic (low priority - Background)
              # Incoming connections to listening port
              tcp dport 54535 ip dscp set cs1
              udp dport 54535 ip dscp set cs1
            }

            chain output {
              type filter hook output priority mangle; policy accept;

              # Deprioritize outgoing traffic from qBittorrent container (UID 1000)
              # This catches outgoing connections initiated by the container
              meta skuid 1000 ip dscp set cs1
            }
          '';
        };

        systemd.services.cake-qdisc = {
          description = "CAKE QoS on eth0";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # diffserv4 creates 4 tins; qBittorrent (CS1) goes to Background tin
            # No bandwidth limit - uses whatever is available
            ExecStart = "${lib.getExe' pkgs.iproute2 "tc"} qdisc replace dev eth0 root cake diffserv4";
            ExecStop = "${lib.getExe' pkgs.iproute2 "tc"} qdisc del dev eth0 root 2>/dev/null || true";
          };
        };

        systemd.network = {
          enable = true;
          wait-online.enable = false;
          links."40-eth0" = {
            matchConfig.OriginalName = "eth0";
            linkConfig.WakeOnLan = "magic";
          };
          networks = {
            "10-eth" = {
              matchConfig.Name = "eth0";
              address = [ "192.168.0.18/24" ];
              routes = [ { Gateway = "192.168.0.1"; } ];
              dns = [
                "1.1.1.1"
                "1.0.0.1"
              ];
              linkConfig.RequiredForOnline = "routable";
            };
            "20-wifi" = {
              matchConfig.Name = "wlan0";
              linkConfig.RequiredForOnline = "no";
              networkConfig = {
                DHCP = "yes";
                Domains = "~.";
              };
              dhcpV4Config.RouteMetric = 3000;
            };
          };
        };

        networking = {
          wireless.iwd = {
            enable = true;
            settings = {
              General.AddressRandomization = "network";
              Settings.AutoConnect = true;
            };
          };
          useNetworkd = true;
          useDHCP = false;
          nftables.enable = true;
          usePredictableInterfaceNames = false;
          firewall = {
            interfaces.eth0 = {
              allowedTCPPorts = [
                80
                443
                54535
              ];
              allowedUDPPorts = [
                54535
              ];
            };
          };
          nameservers = [
            "1.1.1.1#cloudflare-dns.com"
            "1.0.0.1#cloudflare-dns.com"
          ];
        };

        services.resolved = {
          enable = true;
          settings.Resolve = {
            DNSSEC = true;
            DNSOverTLS = true;
          };
        };
      };
  };
}
