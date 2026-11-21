{ ... }:
{
  den.aspects.nixos-services._.tailscale-trial.nixos =
    { pkgs, ... }:
    let
      settings = pkgs.writeText "tailscale-trial.json" (
        builtins.toJSON {
          version = "alpha0";
          acceptDNS = false;
          acceptRoutes = false;
          advertiseRoutes = [ ];
          exitNode = "";
          netfilterMode = "off";
          runSSHServer = false;
        }
      );
    in
    {
      services.tailscale = {
        enable = true;
        disableTaildrop = true;
        openFirewall = false;
        useRoutingFeatures = "none";
        extraDaemonFlags = [ "--config=${settings}" ];
      };

      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];

      networking.nftables.tables.tailscale-trial = {
        family = "inet";
        content = ''
          chain input {
            type filter hook input priority filter - 1; policy accept;
            iifname "tailscale0" ct state established,related return
            iifname "tailscale0" meta l4proto { icmp, ipv6-icmp } return
            iifname "tailscale0" tcp dport 22 return
            iifname "tailscale0" drop
          }

          chain forward {
            type filter hook forward priority filter - 1; policy accept;
            iifname "tailscale0" drop
            oifname "tailscale0" drop
          }
        '';
      };
    };
}
