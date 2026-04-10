{
  ...
}:
{
  den.aspects.networking = {
    includes = [ ];

    nixos =
      { ... }:
      {
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
