{
  den,
  ...
}:
{
  den.aspects.pi = {
    includes = [
      den.aspects.fleet-unit-state
      den.aspects.backup
      den.aspects.pi-services-backup
      den.aspects.persistence
      den.aspects.service-host
      den.aspects.nixos-services._.automations
      den.aspects.nixos-services._.homeassistant
      den.aspects.nixos-services._.fleet-health
      den.aspects.fleet-controller
      den.aspects.pi-generation-retention
      den.aspects.lan-edge
      den.aspects.deploy-target
      den.aspects.passwordless-sudo
    ];

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

        modules.backup.hostRecovery.enable = true;
        modules.backup.hostRecovery.quiesceUnits = [ "container@homeassistant.service" ];
        modules.backup.hostRecovery.capturePaths = [ "/home/repparw/services/hass" ];
        # Tmpfs-root landing (phase 2): proven twice by the standalone trial in
        # ~/impermanence-pi-test/evidence (thread dd50ec1a). /persist is the
        # former SD root partition; the initrd check-persistence-state guard
        # verifies the prepared identity before activation.
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
          {
            directory = "/var/lib/host-recovery";
            mode = "0700";
          }
        ];

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
          # Preserve the host's existing cap drop-in. Storage is volatile, so
          # SystemMaxUse is currently dormant; RuntimeMaxUse remains active.
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
        zramSwap = {
          enable = true;
          algorithm = "zstd";
          memoryPercent = 25;
        };

        fileSystems = {
          # Root is volatile; the former SD root partition is /persist (see
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

          "/boot/firmware" = {
            device = "/dev/disk/by-partuuid/2178694e-01";
            fsType = "vfat";
          };

          # Backing store for host persistence (phase 1 of the tmpfs-root
          # migration): the existing SD ext4 root, mounted at /persist while
          # / stays ext4. Proves the mount deploys cleanly before
          # impermanence is enabled in phase 2. Layout mirrors the trial
          # configuration that booted twice with PASS (evidence in
          # ~/impermanence-pi-test/evidence, thread dd50ec1a).
          "/persist" = {
            device = "/dev/disk/by-partuuid/2178694e-02";
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

        swapDevices = [
          {
            device = "/home/repparw/.swapfile";
            size = 8192;
          }
        ];

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
