{
  den,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  flake-file.inputs.disko = {
    url = "github:nix-community/disko";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.pi = {
    includes = [
      den.batteries.hostname
      den.aspects.networking
      den.aspects.secrets
    ];

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        # RPi5 config.txt, mirroring nixpkgs' sd-image-aarch64. u-boot is the
        # first-stage bootloader; it then reads extlinux from the ext4 root.
        # [pi5] disables the UART so ghost inputs can't interrupt u-boot
        # (https://bugzilla.opensuse.org/show_bug.cgi?id=1251192).
        configTxt = pkgs.writeText "config.txt" ''
          kernel=u-boot.bin

          # Boot in 64-bit mode.
          arm_64bit=1

          # U-Boot needs this to work, regardless of whether UART is actually used or not.
          enable_uart=1

          # Prevent the firmware from smashing the framebuffer setup done by the mainline kernel
          avoid_warnings=1

          [pi3]
          # Otherwise the serial output will be garbled.
          core_freq=250

          [pi4]
          enable_gic=1
          armstub=armstub8-gic.bin

          # Otherwise the resolution will be weird in most cases
          disable_overscan=1

          # Supported in newer board revisions
          arm_boost=1

          [cm4]
          # Enable host mode on the 2711 built-in XHCI USB controller.
          otg_mode=1

          [cm5]
          dtoverlay=dwc2,dr_mode=host

          [pi5]
          # On some revisions of the RPi5, U-Boot picks up ghost inputs from the
          # uart, interrupting the boot process.
          enable_uart=0
        '';
      in
      {
        imports = [
          inputs.disko.nixosModules.disko
        ];

        # SD card layout managed by disko (only /dev/mmcblk0; the NVMe
        # /home/repparw disk is deliberately NOT listed here, so nixos-anywhere
        # never formats it). GPT with pinned partition GUIDs so the
        # by-partuuid mounts below stay valid across installs. enableConfig is
        # off: the fileSystems below are hand-written on purpose.
        disko = {
          enableConfig = false;
          devices.disk.sd = {
            type = "disk";
            device = "/dev/mmcblk0";
            content = {
              type = "gpt";
              partitions = {
                firmware = {
                  size = "512M";
                  type = "EF00";
                  uuid = "73ede3db-c84d-4604-895a-f18089cbc48e";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot/firmware";
                    # Replicates nixpkgs' sd-image-aarch64 firmware partition:
                    # RPi firmware blobs + device trees + u-boot + config.txt
                    # (kernel=u-boot.bin). Runs on the installer at /mnt.
                    # Note: no start*.elf in the current raspberrypifw package;
                    # the RPi5 EEPROM bootloader loads u-boot.bin directly.
                    postMountHook = ''
                      cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bootcode.bin ${pkgs.raspberrypifw}/share/raspberrypi/boot/fixup*.dat /mnt/boot/firmware/
                      cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bcm2712*.dtb /mnt/boot/firmware/
                      cp ${pkgs.ubootRaspberryPiAarch64}/u-boot.bin /mnt/boot/firmware/
                      cp ${pkgs.raspberrypi-armstubs}/armstub8-gic.bin /mnt/boot/firmware/
                      cp ${configTxt} /mnt/boot/firmware/config.txt
                    '';
                  };
                };
                root = {
                  size = "100%";
                  type = "8300";
                  uuid = "b7317088-8461-46c5-9458-a5789a071498";
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/";
                  };
                };
              };
            };
          };
        };

        # Raspberry Pi 5 (aarch64) triple-boot loader: firmware (u-boot +
        # config.txt) lives on the vfat /boot/firmware partition, while NixOS
        # writes the extlinux boot files into /boot on the ext4 root.
        boot = {
          kernelPackages = pkgs.linuxPackages_latest;
          kernelParams = [
            "console=ttyMA0,115200n8"
            "console=tty0"
          ];
          loader = {
            grub.enable = false;
            generic-extlinux-compatible.enable = true;
          };
        };

        fileSystems = {
          "/" = {
            device = "/dev/disk/by-partuuid/b7317088-8461-46c5-9458-a5789a071498";
            fsType = "ext4";
            options = [
              "defaults"
              "noatime"
            ];
          };

          "/boot/firmware" = {
            device = "/dev/disk/by-partuuid/73ede3db-c84d-4604-895a-f18089cbc48e";
            fsType = "vfat";
          };

          # User home + Home Assistant data live on the NVMe, so the pod's
          # ~/services/hass carries over from the Debian install unchanged.
          "/home/repparw" = {
            device = "/dev/disk/by-partuuid/7fd52c5b-01";
            fsType = "ext4";
            options = [
              "defaults"
              "noatime"
            ];
          };
        };

        swapDevices = [ ];

        # Rootless podman's rootlessport must bind host port 80 for the HA pod
        # (hostPort: 80 below). Debian allowed this via ip_unprivileged_port_start=80;
        # NixOS defaults to 1024, which would make the bind fail.
        boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 80;

        hardware.bluetooth.enable = true;

        virtualisation.podman = {
          enable = true;
          autoPrune.enable = true;
        };

        nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

        # LAN DNS server: resolved listens on the LAN address and proxies to
        # Cloudflare/Quad9 over DoT.
        services.resolved.settings.Resolve = {
          DNS = [
            "1.1.1.1#cloudflare-dns.com"
            "1.0.0.1#cloudflare-dns.com"
          ];
          FallbackDNS = [ "9.9.9.9#dns.quad9.net" ];
          DNSSEC = true;
          DNSOverTLS = true;
          Cache = true;
          DNSStubListenerExtra = "192.168.0.4:53";
        };

        networking = {
          # First boot / install note: the resolver chain above only comes up
          # once this static address is configured (systemd.network below).
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
          hosts = {
            "192.168.0.18" = [
              "repparw.com"
              "code.repparw.com"
              "auth.repparw.com"
              "bazarr.repparw.com"
              "broker.repparw.com"
              "changedetection.repparw.com"
              "ddclient.repparw.com"
              "rss.repparw.com"
              "jellyfin.repparw.com"
              "mercury.repparw.com"
              "ntfy.repparw.com"
              "paperdb.repparw.com"
              "paper.repparw.com"
              "profilarr.repparw.com"
              "prowlarr.repparw.com"
              "qbit.repparw.com"
              "radarr.repparw.com"
              "seerr.repparw.com"
              "sockpuppetbrowser.repparw.com"
              "sonarr.repparw.com"
              "traefik.repparw.com"
              "valkey.repparw.com"
              "home.repparw.com"
            ];
            "192.168.0.4" = [
              "hyperion.repparw.com"
              "pihole.repparw.com"
            ];
          };

          firewall.interfaces.eth0 = {
            allowedTCPPorts = [
              80
              53
            ];
            allowedUDPPorts = [
              53
              60001
            ];
          };
        };
      };
  };

  # Minimal headless repparw: same account as alpha but without the desktop
  # stack. Mirrors the Debian-era setup on the pi (fish shell, ssh keys, and
  # the rootless podman Home Assistant pod below).
  den.aspects.pi-repparw = {
    includes = [
      den.batteries.define-user
      den.batteries.primary-user
      (den.batteries.user-shell "fish")
      den.aspects.shell
      den.aspects.tmux
      den.aspects.git
      den.aspects.ssh
    ];

    user = _: {
      linger = true;
      description = "repparw";
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

    provides.to-hosts = {
      nixos =
        { ... }:
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "hm-backup";
          };
        };
    };

    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        xdg.enable = true;
        home.preferXdgDirectories = true;

        # Home Assistant pod: kept as a rootless podman kube manifest so the
        # data under ~/services/hass and the container layout from the Debian
        # installation carry over unchanged. `podman kube play --replace` is
        # the NixOS-managed equivalent of the on-pi quadlet services.kube.
        home.file."services/pod.yaml".text = ''
          # Save the output of this file and use kubectl create -f to import
          # it into Kubernetes.
          #
          # Created with podman-5.4.2

          # NOTE: The namespace sharing for a pod has been modified by the user and is not the same as the
          # default settings for kubernetes. This can lead to unexpected behavior when running the generated
          # kube yaml in a kubernetes cluster.
          ---
          apiVersion: v1
          kind: Pod
          metadata:
            annotations:
              io.containers.autoupdate/homeassistant: registry
              io.kubernetes.cri-o.SandboxID/homeassistant: 4bf37bb3e42a602c9ae39b84f7c1bb02525c6d9b73df1fce83680bc5454621cb
            creationTimestamp: "2026-02-16T14:54:45Z"
            labels:
              app: podservices
            name: podservices
          spec:
            containers:
            - image: docker.io/homeassistant/home-assistant:stable
              name: homeassistant
              ports:
              - containerPort: 8123
                hostPort: 80
              securityContext:
                privileged: true
                procMount: Unmasked
              volumeMounts:
              - mountPath: /config
                name: home-repparw-services-hass-host-0
              - mountPath: /etc/localtime
                name: etc-localtime-host-1
                readOnly: true
              - mountPath: /run/dbus
                name: run-dbus-host-2
                readOnly: true
            volumes:
            - hostPath:
                path: /home/repparw/services/hass
                type: Directory
              name: home-repparw-services-hass-host-0
            - hostPath:
                path: /etc/localtime
                type: File
              name: etc-localtime-host-1
            - hostPath:
                path: /run/dbus
                type: Directory
              name: run-dbus-host-2
        '';

        systemd.user.services."podservices-homeassistant" = {
          Unit.Description = "Home Assistant pod (podman kube)";
          Unit.After = [ "network-online.target" ];
          Service = {
            Type = "simple";
            ExecStart = "${lib.getExe pkgs.podman} kube play --replace ${config.home.homeDirectory}/services/pod.yaml";
            ExecStop = "${lib.getExe pkgs.podman} kube down --force ${config.home.homeDirectory}/services/pod.yaml";
            Restart = "always";
            RestartSec = "10s";
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
  };

  den.hosts.aarch64-linux.pi.users.repparw = {
    aspect = den.aspects.pi-repparw;
  };
}
