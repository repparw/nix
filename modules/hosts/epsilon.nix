{
  den,
  lib,
  ...
}:
{
  den.aspects.epsilon = {
    includes = [
      den.batteries.hostname
      den.aspects.networking
      # den.aspects.nix (in den.default) declares sops.secrets.accessTokens;
      # without the secrets aspect the sops-nix module is missing entirely.
      den.aspects.secrets
    ];
    nixos =
      { config, lib, ... }:
      {
        imports = [
          # Glance migrated off pi (phase 3, first piece): the dashboard is
          # stateless, so it runs as a local container here behind the
          # terminating edge. Definitions schema comes along for the ride.
          ../service-definitions.nix
          ../_services/inventory.nix
          ../_services/glance.nix
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
          # Monitors probe public names; container resolution mirrors
          # epsilon edge routing (apex -> local glance, vhosts -> pi).
          config.networking.hosts = {
            "192.168.0.4" = [
              "auth.repparw.com"
              "bazarr.repparw.com"
              "finance.repparw.com"
              "home.repparw.com"
              "jellyfin.repparw.com"
              "paper.repparw.com"
              "prowlarr.repparw.com"
              "qbit.repparw.com"
              "radarr.repparw.com"
              "rss.repparw.com"
              "sonarr.repparw.com"
            ];
            "10.231.137.15" = [ "repparw.com" ];
          };
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
        ];
        # Egress NAT for ve-* comes from systemd's io.systemd.nat masquerade;
        # do not layer networking.nat on top.
        networking.firewall.extraForwardRules = ''
          iifname "ve-glance" oifname "wg-home" ip daddr { 192.168.0.0/24 } accept comment "glance monitor checks via home tunnel"
          iifname "wg-home" oifname "ve-glance" ct state established,related accept comment "glance monitor replies"
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

        # Public VPS: no mosh UDP range exposed.
        programs.mosh.openFirewall = lib.mkForce false;

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

        # Phase 2 public edge: terminate TLS here on a wildcard cert
        # (Cloudflare DNS-01, same token pi uses), then forward every vhost
        # to pi's traefik over the tunnel with the original Host preserved.
        # Internal routing, authelia, and every backend stay untouched.
        # Phase 3 swaps this block for the full edge aspect as stateful
        # pieces migrate off pi.
        sops.secrets.cloudflare.sopsFile = ../../secrets/proxy.sops.yaml;

        services.traefik = {
          enable = true;
          environmentFiles = [ config.sops.secrets.cloudflare.path ];
          dataDir = "/var/lib/traefik";
          staticConfigOptions = {
            entryPoints.websecure = {
              address = ":443";
              asDefault = true;
              forwardedHeaders.trustedIPs = [
                "173.245.48.0/20"
                "103.21.244.0/22"
                "103.22.200.0/22"
                "103.31.4.0/22"
                "141.101.64.0/18"
                "108.162.192.0/18"
                "190.93.240.0/20"
                "188.114.96.0/20"
                "197.234.240.0/22"
                "198.41.128.0/17"
                "162.158.0.0/15"
                "104.16.0.0/13"
                "104.24.0.0/14"
                "172.64.0.0/13"
                "131.0.72.0/22"
              ];
              http.tls.certResolver = "cloudflare";
            };
            ping = { };
            certificatesResolvers.cloudflare.acme = {
              email = "ubritos@gmail.com";
              storage = "/var/lib/traefik/acme.json";
              dnsChallenge = {
                provider = "cloudflare";
                resolvers = [
                  "1.1.1.1:53"
                  "1.0.0.1:53"
                ];
              };
            };
          };
          dynamicConfigOptions = {
            http = {
              routers = {
                # Apex serves the local glance; everything else falls
                # through to pi's traefik via the catch-all below.
                apex-glance = {
                  rule = "Host(`repparw.com`)";
                  entryPoints = [ "websecure" ];
                  service = "glance-local";
                  priority = 100;
                };
                catch-all = {
                  rule = "PathPrefix(`/`)";
                  entryPoints = [ "websecure" ];
                  service = "home-edge";
                  tls = {
                    certResolver = "cloudflare";
                    domains = [
                      {
                        main = "*.repparw.com";
                        sans = [ "repparw.com" ];
                      }
                    ];
                  };
                };
              };
              serversTransports.home-edge-tls = {
                insecureSkipVerify = true;
                # pi's websecure entrypoint runs sniStrict; dialing it by IP
                # sends no SNI and the handshake gets dropped before routing.
                serverName = "repparw.com";
              };
              services = {
                glance-local.loadBalancer.servers = [ { url = "http://10.231.137.15:8080"; } ];
                home-edge.loadBalancer = {
                  passHostHeader = true;
                  serversTransport = "home-edge-tls";
                  servers = [ { url = "https://192.168.0.4:443"; } ];
                };
              };
            };
          };
        };

        networking.firewall.interfaces.eth0.allowedTCPPorts = [ 443 ];

        # Rescue path: root keeps key access with the same shared keys.
        users.users.root.openssh.authorizedKeys.keys = import ../../authorized-keys.nix;
      };
  };

  # Headless repparw on epsilon: same base account as pi, which carries the
  # authorized keys for alpha and pi access.
  den.hosts.aarch64-linux.epsilon.users.repparw.aspect = den.aspects.repparw;
}
