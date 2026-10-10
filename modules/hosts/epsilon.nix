{
  den,
  lib,
  ...
}:
{
  flake-file.inputs.hermes-agent.url = "github:NousResearch/hermes-agent/v2026.8.19";

  den.aspects.epsilon = {
    includes = [
      den.aspects.fleet-unit-state
      den.aspects.deploy-target
      den.aspects.passwordless-sudo
      den.aspects.backup
      den.aspects.persistence
      den.aspects.service-host
      den.aspects.nixos-services._.edge
      den.aspects.nixos-services._.hermes
      den.aspects.nixos-services._.archisteamfarm
      den.aspects.nixos-services._.paperless
    ];
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        imports = [ ../_services/glance.nix ];

        sops.secrets.repparwPasswordHash = {
          sopsFile = ../../secrets/users-epsilon.sops.yaml;
          key = "repparwPasswordHash";
          neededForUsers = true;
        };
        # users.mutableUsers stays true: this is a creation-time bootstrap,
        # not an activation-time password reset.
        users.users.repparw.hashedPasswordFile = config.sops.secrets.repparwPasswordHash.path;

        modules.services.bridgePrefix = "10.231.137";

        modules.backup.hostRecovery.enable = true;
        modules.backup.paths = [
          "/home/containers/config"
          "/var/lib/ddclient"
        ];
        # Tmpfs-root landing (phase 2): mirrors the pi landing (#180 + #182).
        # /persist is the former ext4 root partition; the initrd
        # check-persistence-state guard verifies the prepared identity before
        # activation. /nix is a directory on the backing volume and is bound
        # into place via fileSystems below (neededForBoot: the store must be
        # visible to the initrd before activation).
        modules.persistence.enable = true;
        modules.persistence.mutableAccounts = true;
        # The aspect's random-seed symlink cannot transition on this host: /
        # and /persist are the same filesystem during the migration, so the
        # live symlink would point at itself (ELOOP) and fail every deploy-rs
        # switch. The seed is regenerated per boot instead; directory binds
        # are unaffected. Revisit if the backing volume ever splits from /.
        environment.persistence."/persist".files = lib.mkForce [ ];

        environment.persistence."/persist".directories = [
          {
            directory = "/home/repparw";
            user = "repparw";
            group = "users";
            mode = "0700";
          }
          {
            directory = "/home/containers/config";
            user = "repparw";
            group = "users";
          }
          {
            directory = "/var/lib/ddclient";
            user = "ddclient";
            group = "ddclient";
          }
          "/var/log"
        ];

        containers.glance.config.networking.hosts = {
          "${config.containers.glance.localAddress}" = [ config.modules.services.domain ];
        };
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
        # The store bind must be up before the initrd activation script runs,
        # mirroring the aspect's sysroot-var-lib-nixos wiring.
        boot.initrd.systemd.mounts = [
          {
            where = "/sysroot/nix";
            what = "/sysroot/persist/nix";
            type = "none";
            options = "bind";
            requires = [ "sysroot-persist.mount" ];
            after = [ "sysroot-persist.mount" ];
            wantedBy = [ "initrd-fs.target" ];
          }
        ];
        boot.initrd.systemd.services.initrd-nixos-activation = {
          requires = [ "sysroot-nix.mount" ];
          after = [ "sysroot-nix.mount" ];
        };

        boot.initrd.availableKernelModules = [
          "virtio_scsi"
          "virtio_pci"
          "virtio_blk"
        ];

        fileSystems = {
          # Root is volatile; the former ext4 root partition is /persist (see
          # the phase-1 mounts below). Impermanence binds the prepared state
          # back into place at boot after check-persistence-state verifies it.
          "/" = {
            device = "tmpfs";
            fsType = "tmpfs";
            options = [
              "x-initrd.mount"
              "mode=0755"
              "size=50%"
            ];
          };

          # The store lives on the backing volume (single-disk VM). It is
          # exposed via an initrd mount below, NOT a fileSystems entry: a
          # fileSystems."/nix" declaration makes the GRUB generator treat
          # /nix as a separate store filesystem and write kernel paths
          # without the /nix prefix, which leaves every menu entry unable
          # to load its kernel (recovered manually via the GRUB shell,
          # ~/impermanence-pi-test/evidence/).

          # Backing store for host persistence (phase 1 of the tmpfs-root
          # migration): the existing ext4 root, mounted at /persist while /
          # stays ext4. Proves the mount deploys before impermanence is
          # enabled in phase 2; mirrors the pi landing (#178).
          "/persist" = {
            device = "/dev/disk/by-partuuid/daa9a574-99f0-449e-b43a-463650870efb";
            fsType = "ext4";
            neededForBoot = true;
          };

          "/boot" = {
            device = "/persist/boot";
            fsType = "none";
            options = [ "bind" ];
            depends = [ "/persist" ];
          };

          "/boot/efi" = {
            device = "/dev/disk/by-uuid/4DD2-903D";
            fsType = "vfat";
          };
        };

        zramSwap.enable = true;

        networking.interfaces.eth0.useDHCP = true;
        services.resolved.settings.Resolve.DNSStubListenerExtra =
          "${config.modules.services.bridgePrefix}.1";

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
          iifname "eth0" meta mark 0x484f4d45 tcp dport 443 accept comment "home uplink https"
          iifname "eth0" meta mark 0x484f4d45 tcp dport 22 accept comment "home uplink ssh"
          iifname "eth0" meta mark 0x484f4d45 udp dport 60002 accept comment "home uplink mosh"
          iifname "ve-*" ip daddr ${config.modules.services.bridgePrefix}.1 meta l4proto { tcp, udp } th dport 53 accept comment "container DNS"
        '';
        # Home-uplink allowlists cannot take a SOPS value: firewall strings
        # render at evaluation time. An accept verdict in an earlier base
        # chain does not bypass later base chains. An empty set matches
        # nothing, so a missing secret fails closed.
        networking.nftables.tables.home-wan = {
          family = "inet";
          content = ''
            set home_wan {
              type ipv4_addr
            }

            chain input {
              type filter hook input priority filter - 1; policy accept;
              iifname "eth0" ip saddr @home_wan meta mark set 0x484f4d45 comment "tag home uplink"
              iifname "eth0" ip saddr @home_wan tcp dport 443 accept comment "fleet health over split DNS"
              iifname "eth0" ip saddr @home_wan tcp dport 22 accept comment "ssh from home"
              iifname "eth0" ip saddr @home_wan udp dport 60002 accept comment "mosh from home"
            }
          '';
        };
        networking.nftables.tables.container-egress-nat = {
          family = "ip";
          content = ''
            chain postrouting {
              type nat hook postrouting priority 100; policy accept;
              ip saddr ${config.modules.services.bridgePrefix}.0/24 oifname { "eth0", "wg-home" } masquerade
            }
          '';
        };

        programs.mosh.openFirewall = lib.mkForce false;
        services.openssh.openFirewall = lib.mkForce false;
        networking.firewall.interfaces."wg-home".allowedTCPPorts = [ 22 ];
        networking.firewall.interfaces."wg-home".allowedUDPPorts = [ 60002 ];

        sops.secrets = {
          wgEpsilonPrivateKey.sopsFile = ../../secrets/wg.sops.yaml;
          wgEpsilonPresharedKey.sopsFile = ../../secrets/wg.sops.yaml;
          homeWanIp = {
            sopsFile = ../../secrets/home.sops.yaml;
            restartUnits = [ "home-wan.service" ];
          };
        };

        systemd.services.home-wan = {
          description = "Provision home uplink (firewall set + WireGuard endpoint) from secret";
          after = [
            "sops-install-secrets.service"
            "nftables.service"
            "systemd-networkd.service"
          ];
          wants = [ "sops-install-secrets.service" ];
          wantedBy = [ "multi-user.target" ];
          restartTriggers = [ config.sops.secrets.homeWanIp.path ];
          serviceConfig.Type = "oneshot";
          script = ''
            set -euo pipefail
            wanIp=$(tr -d '[:space:]' < ${config.sops.secrets.homeWanIp.path})
            if [[ ! "$wanIp" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
              echo "home-wan: refusing to provision, secret is not an IPv4 address" >&2
              exit 1
            fi
            ${pkgs.nftables}/bin/nft flush set inet home-wan home_wan
            ${pkgs.nftables}/bin/nft add element inet home-wan home_wan "{ $wanIp }"
            for ((i = 0; i < 60; i++)); do
              [ -e /sys/class/net/wg-home ] && break
              ${pkgs.coreutils}/bin/sleep 2
            done
            ${pkgs.wireguard-tools}/bin/wg set wg-home peer "qvjDMgSHda89kuJ0vBL44LAdP681dXMczkSyfk9BnSc=" endpoint "$wanIp:51820"
          '';
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
              persistentKeepalive = 25;
            }
          ];
        };

        networking.firewall.interfaces.eth0.allowedTCPPorts = [ ];

      };
  };

}
