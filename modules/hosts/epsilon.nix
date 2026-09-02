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
      den.batteries.hostname
      den.aspects.networking
      # den.aspects.nix (in den.default) declares sops.secrets.accessTokens;
      # without the secrets aspect the sops-nix module is missing entirely.
      den.aspects.secrets
      # Offsite restic of the stateful edge services + hermes on this host
      # (backup aspect pulls in restic itself).
      den.aspects.backup
      # Edge ingress stack (Traefik, Authelia, Glance, Miniflux, ddclient)
      den.aspects.nixos-services._.edge
      # Hermes Agent gateway.
      den.aspects.nixos-services._.hermes
    ];
    nixos =
      { config, lib, ... }:
      {
        imports = [
          ../service-definitions.nix
          ../_services/inventory.nix
          ../_services/glance.nix
        ];

        # Offsite restic coverage (den.aspects.backup): the stateful edge
        # services (authelia/miniflux) plus hermes agent state.
        modules.backup.paths = [
          "/home/containers/config"
          "/home/repparw/services"
        ];

        # pi's estate uses 10.231.136.0/24 on its own bridge AND that range
        # is routed into the tunnel; epsilon's bridge must not collide.
        # NOTE: redefine the whole entry — overriding a single leaf here
        # silently drops the inventory's mkDefault siblings (port/auth).
        modules.services.definitions.glance = {
          containerAddress = "10.231.137.15";
          port = 8080;
          auth = "bypass";
        };
        containers.glance = {
          hostAddress = lib.mkForce "10.231.137.1";
          # No in-container stub resolver chains: external DNS goes straight
          # out the masqueraded bridge to public resolvers. Monitor names are
          # pinned below and never consult DNS.
          config.services.resolved.enable = false;
          config.networking.nameservers = [
            "1.1.1.1"
            "9.9.9.9"
          ];
          # Monitors probe public endpoints (CF + edge + backends); apex
          # is pinned local, vhosts resolve via public DNS.
          config.networking.hosts = {
            "10.231.137.15" = [ "repparw.com" ];
          };
        };
        containers.hermes = {
          hostAddress = lib.mkForce "10.231.137.1";
          localAddress = lib.mkForce "10.231.137.3";
          autoStart = true;
          privateNetwork = true;
          privateUsers = 327680;
        };
        # Authelia joined epsilon's 10.231.137.0/24 bridge (like glance/hermes);
        # without this it defaulted to pi's 10.231.136.1, pointing its nameserver
        # at a bridge that doesn't exist here, so DNS lookups failed.
        containers.authelia = {
          hostAddress = lib.mkForce "10.231.137.1";
          config.networking.nameservers = lib.mkForce [ "10.231.137.1" ];
        };
        # Miniflux fetched no feeds after migration: it also defaulted to pi's
        # 10.231.136.1 bridge, so its nameserver didn't resolve on epsilon.
        containers.miniflux = {
          hostAddress = lib.mkForce "10.231.137.1";
          config.networking.nameservers = lib.mkForce [ "10.231.137.1" ];
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
        services.resolved.settings.Resolve.DNSStubListenerExtra = [
          "10.231.137.1"
          "10.231.137.3"
        ];
        # Egress NAT for ve-* comes from systemd's io.systemd.nat masquerade;
        # do not layer networking.nat on top.
        networking.firewall.extraForwardRules = ''
          iifname "ve-glance" oifname "wg-home" ip daddr { 192.168.0.0/24 } accept comment "glance monitor checks via home tunnel"
          iifname "wg-home" oifname "ve-glance" ct state established,related accept comment "glance monitor replies"
          iifname "ve-hermes" oifname "wg-home" ip daddr { 192.168.0.0/24 } accept comment "hermes egress to home (DDNS/state)
        '';
        # Debugging bypass: let the home WAN IP hit 443 directly even when
        # the CF-only rule is the structural trust anchor. Goes before CF in
        # extraInputRules so the packet matches here first.
        networking.firewall.extraInputRules = ''
          iifname "eth0" ip saddr 45.237.179.43 tcp dport 443 accept comment "home WAN debug bypass"
          iifname "eth0" tcp dport 443 ip saddr { 173.245.48.0/20, 103.21.244.0/22, 103.22.200.0/22, 103.31.4.0/22, 141.101.64.0/18, 108.162.192.0/18, 131.0.72.0/22, 162.158.0.0/15, 172.64.0.0/13, 188.114.96.0/20, 190.93.240.0/20, 197.234.240.0/22, 198.41.128.0/17, 104.16.0.0-104.27.255.255 } accept comment "CF only"
        '';
        networking.firewall.interfaces."ve-*" = {
          allowedTCPPorts = [ 53 ];
          allowedUDPPorts = [ 53 ];
        };
        networking.nftables.tables.glance-home-nat = {
          family = "ip";
          content = ''
            chain postrouting {
              type nat hook postrouting priority 100; policy accept;
              ip saddr 10.231.137.0/24 oifname "wg-home" masquerade
            }
          '';
        };
        # Egress for hermes agent container: same host bridge, same home
        # tunnel; same /24 masquerade as glance above.
        networking.nftables.tables.hermes-home-nat = {
          family = "ip";
          content = ''
            chain postrouting {
              type nat hook postrouting priority 100; policy accept;
              ip saddr 10.231.137.0/24 oifname "wg-home" masquerade
            }
          '';
        };
        # Miniflux's container-side address (10.231.137.16) races with
        # systemd-networkd's io.systemd.nat masq_saddr population and ends up
        # missing from it, so its general egress is not masqueraded. Pin an
        # explicit rule for this single container (matches io.systemd.nat's
        # shape: no oifname, so it covers all egress). Home-tunnel traffic is
        # already handled by hermes-home-nat above.
        networking.nftables.tables.miniflux-egress-nat = {
          family = "ip";
          content = ''
            chain postrouting {
              type nat hook postrouting priority 100; policy accept;
              ip saddr 10.231.137.16 masquerade
            }
          '';
        };

        # Public VPS: no mosh UDP range exposed. One pinned port for the
        # interactive session (predictive local echo needs mosh's SSP; ssh
        # cannot speculate). Same port answers on the tunnel.
        programs.mosh.openFirewall = lib.mkForce false;
        networking.firewall.interfaces.eth0.allowedUDPPorts = [ 60002 ];
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

        # Rescue path: root keeps key access with the same shared keys.
        users.users.root.openssh.authorizedKeys.keys = import ../../authorized-keys.nix;
      };
  };

  # Headless repparw on epsilon: same base account as pi, which carries the
  # authorized keys for alpha and pi access.
  den.hosts.aarch64-linux.epsilon.users.repparw.aspect = den.aspects.repparw;
}
