{ den, lib, ... }:
{
  den.aspects.wan-ingress-shaping.nixos =
    { config, pkgs, ... }:
    let
      cfg = config.modules.wan-ingress-shaping;
    in
    {
      options.modules.wan-ingress-shaping = {
        enable = lib.mkEnableOption "ingress CAKE shaping of WAN downloads via an IFB device";
        wanInterface = lib.mkOption {
          type = lib.types.str;
          default = "eth0";
          description = "Physical WAN-facing interface whose ingress is shaped.";
        };
        ifbDevice = lib.mkOption {
          type = lib.types.str;
          default = "ifb-wan";
          description = "Name of the IFB device carrying redirected ingress.";
        };
        bandwidth = lib.mkOption {
          type = lib.types.str;
          default = "23Mbit";
          description = "CAKE ceiling for ingress (e.g. 23Mbit). Keep slightly below the measured bottleneck.";
        };
      };

      config = lib.mkIf cfg.enable {
        boot.kernelModules = [
          "ifb"
          "act_mirred"
          "sch_cake"
        ];

        systemd.network.netdevs."30-wan-ingress-ifb" = {
          netdevConfig = {
            Kind = "ifb";
            Name = cfg.ifbDevice;
          };
        };

        systemd.network.networks."30-wan-ingress-ifb" = {
          matchConfig.Name = cfg.ifbDevice;
          linkConfig.RequiredForOnline = "no";
        };

        systemd.services.wan-ingress-shaping = {
          description = "Shape WAN ingress with CAKE via ${cfg.ifbDevice}";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStop = "-${pkgs.iproute2}/bin/tc filter del dev ${cfg.wanInterface} parent ffff: protocol all prio 10";
          };
          script = ''
            set -euo pipefail
            TC=${pkgs.iproute2}/bin/tc
            IP=${pkgs.iproute2}/bin/ip
            for i in $(seq 1 30); do
              if "$IP" link show ${cfg.wanInterface} >/dev/null 2>&1 && "$IP" link show ${cfg.ifbDevice} >/dev/null 2>&1; then
                break
              fi
              sleep 1
            done
            "$IP" link set ${cfg.ifbDevice} up
            "$TC" qdisc replace dev ${cfg.wanInterface} handle ffff: ingress
            "$TC" filter replace dev ${cfg.wanInterface} parent ffff: protocol all prio 10 u32 match u32 0 0 action mirred egress redirect dev ${cfg.ifbDevice}
            "$TC" qdisc replace dev ${cfg.ifbDevice} root cake bandwidth ${cfg.bandwidth} diffserv4 triple-isolate nonat nowash no-ack-filter split-gso rtt 100ms raw overhead 0
          '';
        };
      };
    };
}
