_: {
  den.aspects.networking = {
    provides.home = { host, ... }: {
      nixos = {
        systemd.network.networks."10-eth" = {
          matchConfig.Name = "eth0";
          address = [ "${host.lanAddress}/24" ];
          routes = [ { Gateway = "192.168.0.1"; } ];
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = true;
            IPv6PrivacyExtensions = false;
          };
          ipv6AcceptRAConfig = {
            UseDNS = false;
            DHCPv6Client = false;
          };
        };

        networking.nftables.tables.lan-server-ipv6 = {
          family = "ip6";
          content = ''
            chain input {
              type filter hook input priority filter - 1; policy accept;
              iifname "eth0" ip6 daddr 2000::/3 meta l4proto { tcp, udp } ct state { new, untracked } counter drop comment "keep LAN services off global IPv6"
            }
            chain forward {
              type filter hook forward priority filter - 1; policy accept;
              iifname "eth0" ip6 daddr 2000::/3 meta l4proto { tcp, udp } ct state { new, untracked } counter drop comment "keep forwarded traffic off global IPv6"
            }
          '';
        };
      };
    };

    nixos =
      { lib, ... }:
      {
        programs.mosh = {
          enable = true;
          openFirewall = true;
        };

        services = {
          fail2ban.enable = true;
          openssh = {
            enable = true;
            openFirewall = true;
            settings.PasswordAuthentication = false;
          };
          tailscale = {
            enable = true;
            disableTaildrop = true;
            extraSetFlags = [
              "--accept-dns=true"
              "--accept-routes=false"
              "--netfilter-mode=off"
            ];
          };
        };

        systemd.network = {
          enable = true;
          wait-online.enable = false;
        };

        networking = {
          useNetworkd = true;
          useDHCP = false;
          nftables.enable = true;
          usePredictableInterfaceNames = false;
          firewall.checkReversePath = false;
          firewall.trustedInterfaces = [ "tailscale0" ];
          nameservers = [
            "1.1.1.1#cloudflare-dns.com"
            "1.0.0.1#cloudflare-dns.com"
            "9.9.9.9#dns.quad9.net"
          ];
        };

        # Strict DoT stalled queries 5s per server when the idle 853 session
        # silently died across NAT/idle drops (#325: headless hosts now use
        # plain DNS, alpha keeps DoT). TimeoutSec bounds each attempt so a
        # dead session costs ~2s per server instead of 5s — with three
        # upstreams the worst case is ~6s, inside the glance monitor's 10s
        # check timeout and near the fleet-health probe's 6s budget.
        services.resolved = {
          enable = true;
          settings.Resolve = {
            DNSOverTLS = lib.mkDefault false;
            TimeoutSec = "2s";
            StaleRetentionSec = "15min";
          };
        };
      };
  };
}
