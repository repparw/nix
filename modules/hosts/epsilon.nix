{
  den,
  lib,
  ...
}:
{
  flake-file.inputs.hermes-agent = {
    url = "github:NousResearch/hermes-agent/v0.23.4";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.epsilon = {
    includes = [
      den.aspects.managed-server
      den.aspects.monitoring._.dashboard
      den.aspects.epsilon._.backup
      den.aspects.nixos-services._.edge
      den.aspects.nixos-services._.hermes
      den.aspects.nixos-services._.grafana-alert-triage
      den.aspects.nixos-services._.automations
      den.aspects.nixos-services._.archisteamfarm
      den.aspects.nixos-services._.paperless
    ];
    provides.backup = {
      includes = [
        den.aspects.host-backup
        den.aspects.monitoring._.backup
      ];
      nixos = { config, ... }: {
        modules.backup.exports = {
          miniflux = {
            unit = "miniflux-backup.service";
            machine = "miniflux";
            path = config.modules.services.definitions.miniflux.backup.path;
            pattern = "miniflux-backup-*.sql.gz";
          };
          paperless = {
            unit = "paperless-exporter.service";
            machine = "paperless";
            path = config.modules.services.definitions.paperless.backup.path;
            pattern = "manifest.json";
          };
        };
      };
    };
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        imports = [ ../_services/glance.nix ];

        nix.settings = {
          max-jobs = 1;
          cores = 1;
        };

        sops.secrets.repparwPasswordHash = {
          sopsFile = ../../secrets/users-epsilon.sops.yaml;
          key = "repparwPasswordHash";
          neededForUsers = true;
        };
        users.users.repparw.hashedPasswordFile = config.sops.secrets.repparwPasswordHash.path;

        sops.secrets.grafana-alert-triage-token = {
          sopsFile = ../../secrets/grafana-alert-triage-epsilon.sops.yaml;
          restartUnits = [ "grafana-alert-triage.service" ];
        };
        modules.grafana-alert-triage = {
          enable = true;
          tokenFile = config.sops.secrets.grafana-alert-triage-token.path;
        };

        modules.services.bridgePrefix = "10.231.137";
        modules.monitoring.health.disks = [
          {
            mount = "/persist";
            warn = 70;
            crit = 85;
          }
        ];

        modules.backup.paths = [ "/home/containers/config" ];
        modules.persistence.enable = true;
        modules.persistence.mutableAccounts = true;

        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/credential-remediation";
            mode = "0700";
          }
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
          "/var/log"
        ];

        containers.glance.config.networking.hosts =
          let
            monitored = lib.attrValues (
              lib.filterAttrs (
                _: service: service.monitor && service.hostname != null && service.port != null
              ) config.modules.services.definitions
            );
            fqdnsFor =
              lanEdge:
              map (service: "${service.hostname}.${config.modules.services.domain}") (
                lib.filter (service: service.lanEdge == lanEdge) monitored
              );
          in
          {
            "${config.containers.glance.localAddress}" = [ config.modules.services.domain ];
            "${config.modules.services.bridgePrefix}.1" = fqdnsFor false;
            "${builtins.getAttr config.modules.services.lanEdgeHost config.modules.services.hostAddresses}" =
              fqdnsFor true;
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
            # Both store aliases become bind mounts after boot. Copy boot
            # assets to /boot so GRUB never derives paths from those mounts.
            copyKernels = true;
            mirroredBoots = lib.mkForce [
              {
                devices = [ "nodev" ];
                path = "/persist/boot";
                efiSysMountPoint = "/boot/efi";
              }
            ];
          };
        };
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
          "/" = {
            device = "tmpfs";
            fsType = "tmpfs";
            options = [
              "x-initrd.mount"
              "mode=0755"
              "size=50%"
            ];
          };

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
          iifname "ve-glance" oifname "tailscale0" ip daddr { ${config.modules.services.hostAddresses.alpha}, ${config.modules.services.hostAddresses.pi} } accept comment "glance monitor checks via tailscale"
          iifname "ve-glance" oifname "ve-paperless" ip daddr ${config.containers.paperless.localAddress} tcp dport ${toString config.modules.services.definitions.paperless.port} accept comment "glance paperless monitor check"
          iifname "ve-hermes" oifname "tailscale0" ip daddr { ${config.modules.services.hostAddresses.alpha}, ${config.modules.services.hostAddresses.pi} } accept comment "hermes egress to home hosts via tailscale"
          iifname "tailscale0" oifname { "ve-glance", "ve-hermes" } ct state established,related accept comment "container tailscale replies"
        '';
        networking.firewall.extraInputRules = ''
          iifname "ve-glance" ip daddr ${config.modules.services.bridgePrefix}.1 tcp dport 443 accept comment "Glance local HTTPS service probes"
          iifname "ve-*" ip daddr ${config.modules.services.bridgePrefix}.1 meta l4proto { tcp, udp } th dport 53 accept comment "container DNS"
        '';
        networking.nftables.tables.container-egress-nat = {
          family = "ip";
          content = ''
            chain postrouting {
              type nat hook postrouting priority 100; policy accept;
              ip saddr ${config.modules.services.bridgePrefix}.0/24 oifname { "eth0", "tailscale0" } masquerade
            }
          '';
        };

        programs.mosh.openFirewall = lib.mkForce false;
        services.openssh.openFirewall = lib.mkForce false;

        networking.firewall.interfaces.eth0.allowedTCPPorts = [ ];

      };
  };

}
