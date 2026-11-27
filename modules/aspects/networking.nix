_: {
  den.aspects.networking = {
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

        systemd.services.iwd.wantedBy = lib.mkForce [ ];
      };
  };
}
