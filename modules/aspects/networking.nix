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
          nameservers = [
            "1.1.1.1#cloudflare-dns.com"
            "1.0.0.1#cloudflare-dns.com"
          ];
        };

        services.resolved = {
          enable = true;
          settings.Resolve = {
            DNSOverTLS = true;
          };
        };

        # Defer iwd since ethernet is primary; wifi is backup only.
        # Remove it from multi-user.target so it does not block boot.
        systemd.services.iwd.wantedBy = lib.mkForce [ ];
      };
  };
}
