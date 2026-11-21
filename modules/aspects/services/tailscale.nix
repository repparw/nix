{ ... }:
{
  den.aspects.nixos-services._.tailscale.nixos =
    { pkgs, ... }:
    let
      settings = pkgs.writeText "tailscale.json" (
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

      networking.firewall.trustedInterfaces = [ "tailscale0" ];

      networking.nftables.tables.tailscale = {
        family = "inet";
        content = ''
          chain forward {
            type filter hook forward priority filter - 1; policy accept;
            iifname "tailscale0" drop
            oifname "tailscale0" drop
          }
        '';
      };
    };
}
