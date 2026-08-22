{
  den,
  lib,
  pkgs,
  ...
}:
{
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
      {
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
          # SD card (mmcblk0): flashed from the official NixOS aarch64
          # sd-image, whose dos partition table yields these PARTUUIDs.
          "/" = {
            device = "/dev/disk/by-partuuid/2178694e-02";
            fsType = "ext4";
            options = [
              "defaults"
              "noatime"
            ];
          };

          "/boot/firmware" = {
            device = "/dev/disk/by-partuuid/2178694e-01";
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

        # Trial validated 2026-08-22; replaced the quadlet kube pod.
        containers.homeassistant = {
          autoStart = true;
          privateNetwork = true;
          hostAddress = "10.231.136.1";
          localAddress = "10.231.136.2";
          bindMounts."/var/lib/hass" = {
            hostPath = "/home/repparw/services/hass";
            isReadOnly = false;
          };
          config =
            { ... }:
            {
              # nspawn breaks host-resolved (loopback stub); use the pi's own
              # LAN resolver over the bridge.
              networking.useHostResolvConf = false;
              networking.nameservers = [ "192.168.0.4" ];

              services.home-assistant = {
                enable = true;
                configDir = "/var/lib/hass";
                extraComponents = [
                  "default_config"
                  "wake_on_lan"
                  "google_assistant"
                  "met"
                  "radio_browser"
                  "google_translate"
                ];
                extraPackages =
                  ps: with ps; [
                    aiogithubapi # hacs
                    aiofiles
                    jinja2
                    joserfc # auth_oidc
                    anthropic
                    litellm
                    pyyaml # ai_automation_suggester
                  ];
              };
              networking.firewall.allowedTCPPorts = [ 8123 ];
              system.stateVersion = "26.05";
            };
        };

        # Ingress for the HA container (nginx adds the X-Forwarded-* headers
        # that the container's trusted_proxies expect).
        services.nginx = {
          enable = true;
          recommendedProxySettings = true;
          virtualHosts."home.repparw.com" = {
            locations."/" = {
              proxyPass = "http://10.231.136.2:8123";
              proxyWebsockets = true;
            };
          };
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

          # Container traffic arrives on the nspawn veth, not eth0: allow its
          # DNS queries to reach the host resolver.
          firewall.interfaces."ve-*" = {
            allowedTCPPorts = [ 53 ];
            allowedUDPPorts = [ 53 ];
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
      # Match the Debian-era uid so the migrated data on the NVMe
      # (/home/repparw) keeps its original ownership.
      uid = 1000;
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
        # installation carry over unchanged. Quadlet (.kube file) generates
        # the systemd user unit with proper sd-notify wiring — a hand-written
        # Type=simple unit would exit as soon as `podman kube play` detaches
        # and tear the pod back down via ExecStop.
        home.file.".config/containers/systemd/podservices.kube".text = ''
          [Kube]
          Yaml=%h/services/pod.yaml
          AutoUpdate=registry

          [Install]
          WantedBy=default.target
        '';

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
      };
  };

  den.hosts.aarch64-linux.pi.users.repparw = {
    aspect = den.aspects.pi-repparw;
  };
}
