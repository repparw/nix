{
  den,
  lib,
  ...
}:
{
  den.aspects.alpha = {
    includes = [
      den.provides.hostname
      den.aspects.auto-upgrade
      den.aspects.cli
      den.aspects.gaming
      den.aspects.logid
      den.aspects.networking
      den.aspects.nixos-services
      den.aspects.overlays
      den.aspects.repparw
      den.aspects.secrets
      den.aspects.style
      den.aspects.streaming
      den.aspects.timers
      den.aspects.virtual-display
    ];

    nixos =
      {
        config,
        lib,
        pkgs,
        modulesPath,
        ...
      }:
      {
        imports = [
          (modulesPath + "/installer/scan/not-detected.nix")
        ];

        boot = {
          initrd = {
            systemd.enable = true;
            availableKernelModules = [
              "nvme"
              "xhci_pci"
              "ahci"
              "usbhid"
              "usb_storage"
              "uas"
              "sd_mod"
            ];
            kernelModules = [ ];
          };
          kernelModules = [ "kvm-amd" ];
          extraModulePackages = [ ];
          loader = {
            systemd-boot = {
              enable = true;
              configurationLimit = 10;
              consoleMode = "max";
            };
            timeout = 1;
            efi.canTouchEfiVariables = true;
          };
        };

        fileSystems = {
          "/" = {
            device = "/dev/disk/by-uuid/51c5e80b-e22e-4d62-a3e2-ebb531deb05b";
            fsType = "btrfs";
            options = [ "subvol=@" ];
          };

          "/boot" = {
            device = "/dev/disk/by-uuid/FBF2-5114";
            fsType = "vfat";
            options = [
              "fmask=0137"
              "dmask=0027"
            ];
          };

          "/mnt/hdd" = {
            fsType = "btrfs";
            label = "HDD";
            options = [
              "noatime"
              "nodiratime"
              "noauto"
              "x-systemd.automount"
              "x-systemd.idle-timeout=60"
              "x-systemd.device-timeout=5s"
              "nofail"
            ];
          };

          "/mnt/seagate" = {
            device = "/dev/disk/by-uuid/979db05c-0fa9-4557-bd92-51f1d10eec3f";
            fsType = "ext4";
            options = [
              "noauto"
              "x-systemd.automount"
              "x-systemd.idle-timeout=60"
              "x-systemd.device-timeout=5s"
              "nofail"
              "nosuid"
              "nodev"
              "relatime"
              "errors=remount-ro"
            ];
          };
        };

        swapDevices = [ ];

        nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
        hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

        programs.obs-studio.enable = true;

        zramSwap.enable = true;

        services = {
          archisteamfarm = {
            enable = true;
            bots.repparw = {
              settings.OnlineStatus = 0;
              username = "ulisesbritos1";
              passwordFile = config.sops.secrets.steamPassword.path;
            };
          };

          beesd.filesystems = {
            root = {
              spec = "LABEL=root";
              hashTableSizeMB = 4096;
              verbosity = "crit";
              extraOptions = [
                "--loadavg-target"
                "5.0"
              ];
            };
            hdd = {
              spec = "LABEL=HDD";
              verbosity = "crit";
              extraOptions = [
                "--loadavg-target"
                "5.0"
              ];
            };
          };

        };
      };

    provides.repparw.homeManager =
      { osConfig, lib, pkgs, ... }:
      let
        cfg = osConfig.modules.services;
        serviceDir = ../_services;

        serviceFiles =
          lib.mapAttrs'
            (name: _: lib.nameValuePair (lib.removeSuffix ".nix" name) (import (serviceDir + "/${name}")))
            (
              lib.filterAttrs (
                name: type: type == "regular" && lib.hasSuffix ".nix" name && !(lib.hasPrefix "_" name)
              ) (builtins.readDir serviceDir)
            );

        extractHostname = rule: lib.removeSuffix "`)" (lib.removePrefix "Host(`" rule);

        getTraefikRule =
          name: attrs: attrs.labels."traefik.http.routers.${name}.rule" or "Host(`${name}.${cfg.domain}`)";

        mkContainer =
          name: attrs:
          let
            traefikRule = getTraefikRule name attrs;
            hostname = extractHostname traefikRule;
            defaultTraefikLabels = {
              "traefik.enable" = "true";
              "traefik.http.routers.${name}.tls" = "true";
              "traefik.http.routers.${name}.rule" = traefikRule;
              "traefik.http.routers.${name}.middlewares" = "authelia@file";
            };

            extraOpts = attrs.extraOptions or [];
            healthCmdOpt = lib.findFirst (opt: lib.hasPrefix "--health-cmd=" opt) null extraOpts;
            healthIntervalOpt = lib.findFirst (opt: lib.hasPrefix "--health-interval=" opt) null extraOpts;
            healthTimeoutOpt = lib.findFirst (opt: lib.hasPrefix "--health-timeout=" opt) null extraOpts;
            healthRetriesOpt = lib.findFirst (opt: lib.hasPrefix "--health-retries=" opt) null extraOpts;

            rawHealthCmd = if healthCmdOpt != null then lib.removePrefix "--health-cmd=" healthCmdOpt else null;
            healthCmd = if rawHealthCmd != null then
              lib.trim (lib.removeSuffix " || exit 1" (lib.removeSuffix "|| exit 1" rawHealthCmd))
            else null;
            healthInterval = if healthIntervalOpt != null then lib.removePrefix "--health-interval=" healthIntervalOpt else null;
            healthTimeout = if healthTimeoutOpt != null then lib.removePrefix "--health-timeout=" healthTimeoutOpt else null;
            healthRetries = if healthRetriesOpt != null then lib.removePrefix "--health-retries=" healthRetriesOpt else null;

            nonHealthOpts = lib.filter (opt:
              !(lib.hasPrefix "--health-cmd=" opt ||
                lib.hasPrefix "--health-interval=" opt ||
                lib.hasPrefix "--health-timeout=" opt ||
                lib.hasPrefix "--health-retries=" opt)
            ) extraOpts;

            quadletContainerConfig = lib.filterAttrs (n: v: v != null) {
              HealthCmd = healthCmd;
              HealthInterval = healthInterval;
              HealthTimeout = healthTimeout;
              HealthRetries = healthRetries;
            };
          in
          {
            image = attrs.image;
            environment = attrs.environment or {};
            environmentFile = attrs.environmentFiles or [];
            volumes = attrs.volumes or [];
            ports = attrs.ports or [];
            labels = (attrs.labels or {}) // defaultTraefikLabels // {
              "io.containers.autoupdate" = "registry";
              "glance.name" = name;
              "glance.url" = "https://${hostname}";
              "glance.icon" = "sh:${name}";
              "glance.same-tab" = "true";
            };
            extraPodmanArgs = nonHealthOpts;
            network = [ "services" ];
            networkAlias = [ name ];
            autoStart = true;
            autoUpdate = "registry";
            exec = if attrs ? cmd then lib.concatStringsSep " " attrs.cmd else null;
            extraConfig = if quadletContainerConfig != {} then { Container = quadletContainerConfig; } else {};
          };

        containersList = lib.attrValues serviceFiles;

        rawContainers = lib.foldl' (acc: def: acc // (def { inherit cfg; config = osConfig; })) { } containersList;

        containers = lib.mapAttrs mkContainer rawContainers;
      in
      {
        services.spotifyd = {
          enable = true;
          settings.global = {
            username = "2ksy00sfypgevoabx2128ia4g";
            device_name = "alpha";
            bitrate = 320;
            max_cache_size = 5000000000;
            initial_volume = 70;
            volume_normalisation = false;
          };
        };

        services.podman = {
          enable = true;
          inherit containers;
          networks.services = {
            driver = "bridge";
          };
        };
      };
  };
}
