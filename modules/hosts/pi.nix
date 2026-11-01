{
  den,
  ...
}:
{
  den.aspects.pi = {
    includes = [
      den.aspects.monitoring._.persist
      den.aspects.monitoring._.cloud
      den.aspects.fleet-unit-state
      den.aspects.pi._.backup
      den.aspects.persistence
      den.aspects.service-host
      den.aspects.nixos-services._.automations
      den.aspects.nixos-services._.homeassistant
      den.aspects.nixos-services._.fleet-health
      den.aspects.nixos-services._.fleet-readiness
      den.aspects.fleet-controller
      den.aspects.pi-generation-retention
      den.aspects.lan-edge
      den.aspects.deploy-target
      den.aspects.passwordless-sudo
    ];

    provides.backup = {
      includes = [
        den.aspects.host-backup
        den.aspects.pi-services-backup
      ];
      nixos = {
        modules.backup.exports.pi-services = {
          unit = "pi-services-backup.service";
          path = "/var/lib/pi-services-backup/current";
          pattern = ".pi-services-export.json";
        };
        modules.backup.paths = [ "/var/lib/pi-services-backup" ];
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
        sops.secrets.repparwPasswordHash = {
          sopsFile = ../../secrets/users-pi.sops.yaml;
          key = "repparwPasswordHash";
          neededForUsers = true;
        };

        # Pi is the deployment controller: it probes the runtime readiness of
        # host-owned upstream waits (Sonarr/Jellyfin, Moonshine PR227) after
        # each Alpha convergence and on its own timer.
        modules.fleet-readiness.enable = true;
        modules.monitoring.health.disks =
          map
            (mount: {
              inherit mount;
              warn = 90;
              crit = 93;
            })
            [
              "/persist"
              "/nix"
              "/home/repparw"
            ];
        modules.persistence.enable = true;
        modules.persistence.mutableAccounts = true;
        modules.backup.paths = [
          "/home/containers/config"
          "/var/lib/auto-update"
          "/var/lib/fleet-health"
          "/var/lib/bluetooth"
          "/var/lib/systemd/rfkill"
        ];

        environment.persistence."/persist".directories = [
          "/home/containers/config"
          "/var/lib/fleet-health"
          "/var/lib/systemd/rfkill"
          {
            directory = "/var/lib/auto-update";
            mode = "0700";
          }
          {
            directory = "/var/lib/bluetooth";
            mode = "0700";
          }
        ];
        # The aspect's random-seed symlink cannot transition on this host: /
        # and /persist are the same filesystem during the migration, so the
        # live symlink would point at itself (ELOOP) and fail every deploy-rs
        # switch. The seed is regenerated per boot instead; directory binds
        # are unaffected. Revisit if the backing volume ever splits from /.
        environment.persistence."/persist".files = lib.mkForce [ ];

        users.users.repparw = {
          uid = 1000;
          # users.mutableUsers stays true: this is a creation-time bootstrap,
          # not an activation-time password reset.
          hashedPasswordFile = config.sops.secrets.repparwPasswordHash.path;
          extraGroups = [ "wheel" ];
          subUidRanges = [
            {
              startUid = 100000;
              count = 65536;
            }
          ];
          subGidRanges = [
            {
              startGid = 100000;
              count = 65536;
            }
          ];
        };

        # /nix is neededForBoot, so stage-1 must enumerate the NVMe: the
        # BCM2712 PCIe host driver is a module (PCIE_BRCMSTB=m) and without
        # it in the initrd the device never appears (90s timeout ->
        # emergency). nvme alone is not enough.
        boot = {
          kernelPackages = pkgs.linuxPackages_latest;
          initrd.availableKernelModules = [
            "pcie_brcmstb"
            "nvme"
            "mmc_block"
            "ext4"
          ];
          kernelParams = [
            "console=ttyMA0,115200n8"
            "console=tty0"
          ];
          loader = {
            grub.enable = false;
            generic-extlinux-compatible.enable = true;
          };
        };

        i18n.supportedLocales = [
          "C.UTF-8/UTF-8"
          "en_US.UTF-8/UTF-8"
          "en_IE.UTF-8/UTF-8"
          "es_AR.UTF-8/UTF-8"
        ];

        services.journald.settings.Journal = {
          Storage = "volatile";
          RuntimeMaxUse = "50M";
          SystemMaxUse = "64M";
        };

        # This preserves the host's existing rule. nixos-rebuild can activate
        # arbitrary NixOS configuration, so this is root-equivalent access, not
        # a meaningful privilege boundary.
        security.sudo.extraRules = [
          {
            users = [ "repparw" ];
            commands = [
              {
                command = "/run/current-system/sw/bin/nixos-rebuild";
                options = [ "NOPASSWD" ];
              }
            ];
          }
        ];

        services.fstrim.enable = true;
        # Disk swap previously lived on the NVMe home partition as an 8G file
        # and never took pages (zram absorbed all swapping) while the partition
        # sat near its 90% health threshold. Zram is the only swap device now,
        # sized up to compensate for the removed file.
        zramSwap = {
          enable = true;
          algorithm = "zstd";
          memoryPercent = 50;
        };

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

          "/boot/firmware" = {
            device = "/dev/disk/by-label/FIRMWARE";
            fsType = "vfat";
          };

          "/persist" = {
            device = "/dev/disk/by-label/NIXOS_SD";
            fsType = "ext4";
            neededForBoot = true;
            options = [
              "defaults"
              "noatime"
              "commit=60"
            ];
          };

          "/boot" = {
            device = "/persist/boot";
            fsType = "none";
            options = [ "bind" ];
            depends = [ "/persist" ];
          };

          "/home/repparw" = {
            device = "/dev/disk/by-partuuid/7fd52c5b-02";
            fsType = "ext4";
            neededForBoot = config.modules.persistence.enable;
            options = [
              "defaults"
              "noatime"
            ]
            # A missing NVMe must not boot into an empty HA/user data directory.
            ++ lib.optional (!config.modules.persistence.enable) "nofail"
            ++ [
              # BCM2712 PCIe link training can take >90s on this board;
              # default device timeout aborted the boot first.
              "x-systemd.device-timeout=5min"
            ];
          };

          "/nix" = {
            device = "/dev/disk/by-partuuid/7fd52c5b-01";
            fsType = "ext4";
            options = [
              "defaults"
              "noatime"
              "x-systemd.device-timeout=5min"
            ];
          };
        };

        hardware.bluetooth.enable = true;

        nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

        networking = {
          nat = {
            enable = true;
            internalInterfaces = [ "ve-+" ];
            externalInterface = "eth0";
            # NOTE: the iifname "ve-+" rule the module renders does not match
            # these veths (observed 2026-08-23: UNREPLIED SYN_SENT conntrack
            # entries while the rule was present). The working masquerade for
            # the container subnet lives in nftables.tables.container-nat below.
          };

          nftables.tables.container-nat = {
            family = "ip";
            content = ''
              chain post {
                type nat hook postrouting priority 90; policy accept;
                ip saddr ${config.modules.services.bridgePrefix}.0/24 oifname "eth0" masquerade
              }
            '';
          };

          interfaces.eth0.ipv4.addresses = [
            {
              address = "192.168.0.4";
              prefixLength = 24;
            }
          ];
          defaultGateway = {
            address = "192.168.0.1";
            interface = "eth0";
          };

          firewall.interfaces.eth0 = {
            allowedUDPPorts = [
              60001
            ];
          };
        };
      };
  };

}
