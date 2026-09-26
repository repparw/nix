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

        systemd.services.iwd.wantedBy = lib.mkForce [ ];
      };

    provides.wan-ingress-shaping = {
      nixos =
        { pkgs, ... }:
        let
          wanInterface = "eth0";
          ifbDevice = "ifb-wan";
          bandwidth = "23Mbit";
        in
        {
          boot.kernelModules = [
            "ifb"
            "act_mirred"
            "sch_cake"
          ];

          systemd.network.netdevs."30-wan-ingress-ifb" = {
            netdevConfig = {
              Kind = "ifb";
              Name = ifbDevice;
            };
          };

          systemd.network.networks."30-wan-ingress-ifb" = {
            matchConfig.Name = ifbDevice;
            linkConfig.RequiredForOnline = "no";
          };

          systemd.services.wan-ingress-shaping = {
            description = "Shape WAN ingress with CAKE via ${ifbDevice}";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStop = "-${pkgs.iproute2}/bin/tc filter del dev ${wanInterface} parent ffff: protocol all prio 10";
            };
            script = ''
              set -euo pipefail
              TC=${pkgs.iproute2}/bin/tc
              IP=${pkgs.iproute2}/bin/ip
              for i in $(seq 1 30); do
                if "$IP" link show ${wanInterface} >/dev/null 2>&1 && "$IP" link show ${ifbDevice} >/dev/null 2>&1; then
                  break
                fi
                sleep 1
              done
              "$IP" link set ${ifbDevice} up
              "$TC" qdisc replace dev ${wanInterface} handle ffff: ingress
              "$TC" filter replace dev ${wanInterface} parent ffff: protocol all prio 10 u32 match u32 0 0 action mirred egress redirect dev ${ifbDevice}
              "$TC" qdisc replace dev ${ifbDevice} root cake bandwidth ${bandwidth} diffserv4 triple-isolate nonat nowash no-ack-filter split-gso rtt 100ms raw overhead 0
            '';
          };
        };
    };
  };
}
