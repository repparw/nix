{
  den.aspects.wg-egress-relay.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      relayUser = "wg-egress-relay";
      bridgeIp = "${config.modules.services.bridgePrefix}.1";
      relayPort = 1080;
      egressTable = 51820;
      tunnelDevice = "sys-subsystem-net-devices-wg\\x2dhome.device";
      iproute2 = pkgs.iproute2;
      privateRoutes = lib.filter (prefix: prefix != "0.0.0.0/0") (
        lib.concatMap (peer: peer.allowedIPs) config.networking.wireguard.interfaces.wg-home.peers
      );
    in
    {
      users.users.${relayUser} = {
        isSystemUser = true;
        group = relayUser;
      };
      users.groups.${relayUser} = { };

      networking.wireguard.interfaces.wg-home.allowedIPsAsRoutes = false;
      systemd.network.networks."40-wg-home".routes = map (prefix: {
        Destination = prefix;
      }) privateRoutes;

      # Egress policy for the relay's UID only: anything the relay sends is
      # routed into the home tunnel. The main table keeps its default via
      # eth0, so management, monitoring, the edge tunnel and backups are
      # unaffected. The blackhole fallback fails closed when the tunnel is
      # down: proxied traffic dies rather than leaking the VPS IP.
      systemd.services.wg-egress-rules = {
        description = "Policy routing for the wg-home egress relay";
        after = [
          tunnelDevice
          "container@hermes.service"
        ];
        bindsTo = [
          tunnelDevice
          "container@hermes.service"
        ];
        partOf = [ "container@hermes.service" ];
        wantedBy = [ "multi-user.target" ];
        before = [ "wg-egress-relay.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          uid="$(${pkgs.coreutils}/bin/id -u ${relayUser})"
          ${iproute2}/bin/ip route replace blackhole default table ${toString egressTable} metric 2048
          ${iproute2}/bin/ip route replace ${config.containers.hermes.localAddress}/32 dev ve-hermes src ${bridgeIp} table ${toString egressTable}
          ${iproute2}/bin/ip route replace default dev wg-home table ${toString egressTable} metric 1024
          ${iproute2}/bin/ip rule del uidrange "$uid-$uid" table ${toString egressTable} priority 5000 2>/dev/null || true
          ${iproute2}/bin/ip rule add uidrange "$uid-$uid" table ${toString egressTable} priority 5000
        '';
        preStop = ''
          uid="$(${pkgs.coreutils}/bin/id -u ${relayUser})"
          ${iproute2}/bin/ip rule del uidrange "$uid-$uid" table ${toString egressTable} priority 5000 2>/dev/null || true
        '';
      };

      systemd.services.wg-egress-relay = {
        description = "SOCKS5 relay with residential egress via the home tunnel";
        after = [ "wg-egress-rules.service" ];
        requires = [ "wg-egress-rules.service" ];
        partOf = [ "wg-egress-rules.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.microsocks}/bin/microsocks -i ${bridgeIp} -p ${toString relayPort}";
          User = relayUser;
          Group = relayUser;
          Restart = "on-failure";
          RestartSec = "5s";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          RestrictAddressFamilies = [
            "AF_INET"
          ];
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
        };
      };

      # Only opted-in containers may reach the relay. Widen by adding an
      # iifname rule here, never by exposing the port further.
      networking.firewall.extraInputRules = ''
        iifname "ve-hermes" ip daddr ${bridgeIp} tcp dport ${toString relayPort} accept comment "hermes residential egress relay"
      '';
    };
}
