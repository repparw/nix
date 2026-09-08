{
  den,
  lib,
  ...
}:
{
  # Hermes Agent ships its own flake (uv2nix package + NixOS module). Keep its
  # dependency closure isolated (no follows) so their tested combination
  # builds unchanged; updates ride tag bumps here.
  flake-file.inputs.hermes-agent.url = "github:NousResearch/hermes-agent/v2026.8.19";

  den.aspects.epsilon = {
    includes = [
      den.aspects.deploy-target
      # Offsite restic of the stateful edge services + hermes on this host
      # (backup aspect pulls in restic itself).
      den.aspects.backup
      den.aspects.service-host
      # Edge ingress stack (Traefik, Authelia, Glance, Miniflux, ddclient)
      den.aspects.nixos-services._.edge
      # Hermes Agent gateway.
      den.aspects.nixos-services._.hermes
      # Steam bot: moved here from pi for VPS uptime (not LAN/exposed).
      den.aspects.nixos-services._.archisteamfarm
    ];
    nixos =
      { config, ... }:
      {
        imports = [ ../_services/glance.nix ];

        modules.services.bridgePrefix = "10.231.137";

        # Offsite restic coverage (den.aspects.backup): the stateful edge
        # services (authelia/miniflux) plus hermes agent state.
        modules.backup.paths = [
          "/home/containers/config"
          "/home/repparw/services"
        ];

        # Glance probes the public routes, except the apex dashboard itself.
        containers.glance.config.networking.hosts = {
          "${config.containers.glance.localAddress}" = [ "repparw.com" ];
        };
        # Oracle Cloud Always Free A1 (VM.Standard.A1.Flex, aarch64, sa-santiago-1).
        # Installed in place via nixos-infect on top of Ubuntu's partition
        # layout: ext4 root on sda1, UEFI ESP on sda15 mounted /boot/efi.
        # The removable GRUB entry needs no NVRAM writes, which OCI VMs
        # do not persist across stop/start.
        boot.loader = {
          efi.efiSysMountPoint = "/boot/efi";
          grub = {
            enable = true;
            efiSupport = true;
            efiInstallAsRemovable = true;
            device = "nodev";
          };
        };
        boot.initrd.availableKernelModules = [
          "virtio_scsi"
          "virtio_pci"
          "virtio_blk"
        ];

        fileSystems = {
          "/" = {
            device = "/dev/disk/by-partuuid/daa9a574-99f0-449e-b43a-463650870efb";
            fsType = "ext4";
          };

          "/boot/efi" = {
            device = "/dev/disk/by-uuid/4DD2-903D";
            fsType = "vfat";
          };
        };

        zramSwap.enable = true;

        # den.aspects.networking disables predictable interface names, so the
        # virtio NIC answers as eth0; OCI hands out everything via DHCP.
        networking.interfaces.eth0.useDHCP = true;
        services.resolved.settings.Resolve.DNSStubListenerExtra =
          "${config.modules.services.bridgePrefix}.1";

        # NixOS containers assign point-to-point addresses and routes itself.
        # Claim these links before systemd's generic 80-container-ve.network,
        # which would otherwise add an unrelated DHCP subnet and its own NAT.
        systemd.network.networks."10-nixos-container" = {
          matchConfig = {
            Kind = "veth";
            Name = "ve-*";
          };
          linkConfig = {
            RequiredForOnline = false;
            Unmanaged = true;
          };
        };

        boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
        networking.firewall.filterForward = true;
        networking.firewall.extraForwardRules = ''
          iifname "ve-*" oifname "eth0" accept comment "container internet egress"
          iifname "eth0" oifname "ve-*" ct state established,related accept comment "container internet replies"
          iifname "ve-glance" oifname "wg-home" ip daddr { 192.168.0.0/24 } accept comment "glance monitor checks via home tunnel"
          iifname "ve-hermes" oifname "wg-home" ip daddr { 192.168.0.0/24 } accept comment "hermes egress to home (DDNS/state)"
          iifname "wg-home" oifname { "ve-glance", "ve-hermes" } ct state established,related accept comment "container home-tunnel replies"
        '';
        networking.firewall.extraInputRules = ''
          iifname "eth0" tcp dport 443 ip saddr { 173.245.48.0/20, 103.21.244.0/22, 103.22.200.0/22, 103.31.4.0/22, 141.101.64.0/18, 108.162.192.0/18, 131.0.72.0/22, 162.158.0.0/15, 172.64.0.0/13, 188.114.96.0/20, 190.93.240.0/20, 197.234.240.0/22, 198.41.128.0/17, 104.16.0.0-104.27.255.255 } accept comment "CF only"
          iifname "eth0" ip saddr 45.237.179.43 tcp dport 443 accept comment "fleet health over split DNS"
          iifname "eth0" ip saddr 45.237.179.43 udp dport 60002 accept comment "mosh from home"
          iifname "ve-*" ip daddr ${config.modules.services.bridgePrefix}.1 meta l4proto { tcp, udp } th dport 53 accept comment "container DNS"
        '';
        # The point-to-point container allocation is represented as a /24 for
        # matching, but only traffic leaving epsilon is source-NATed.
        networking.nftables.tables.container-egress-nat = {
          family = "ip";
          content = ''
            chain postrouting {
              type nat hook postrouting priority 100; policy accept;
              ip saddr ${config.modules.services.bridgePrefix}.0/24 oifname { "eth0", "wg-home" } masquerade
            }
          '';
        };

        # Public VPS: no mosh UDP range exposed. One pinned port for the
        # interactive session (predictive local echo needs mosh's SSP; ssh
        # cannot speculate). Same port answers on the tunnel.
        programs.mosh.openFirewall = lib.mkForce false;
        networking.firewall.interfaces."wg-home".allowedUDPPorts = [ 60002 ];

        # Tunnel home through the router's WireGuard hub (peer registered in
        # the router UI as epsilon, tunnel ip 10.5.5.3). Split-tunnel on
        # purpose: only LAN and pi's container bridge route through it.
        sops.secrets = {
          wgEpsilonPrivateKey.sopsFile = ../../secrets/wg.sops.yaml;
          wgEpsilonPresharedKey.sopsFile = ../../secrets/wg.sops.yaml;
        };

        networking.wireguard.interfaces.wg-home = {
          ips = [ "10.5.5.3/32" ];
          privateKeyFile = config.sops.secrets.wgEpsilonPrivateKey.path;
          peers = [
            {
              publicKey = "qvjDMgSHda89kuJ0vBL44LAdP681dXMczkSyfk9BnSc=";
              presharedKeyFile = config.sops.secrets.wgEpsilonPresharedKey.path;
              allowedIPs = [
                "10.5.5.0/24"
                "192.168.0.0/24"
                "10.231.136.0/24"
              ];
              endpoint = "45.237.179.43:51820";
              persistentKeepalive = 25;
            }
          ];
        };

        networking.firewall.interfaces.eth0.allowedTCPPorts = [ ];

      };
  };

}
