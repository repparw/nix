{
  pkgs,
  inputs,
  config,
  ...
}:
{
  imports = [
    ./cli
    ./gui
    ./services
    ./autoUpgrade.nix
    ./style.nix
    ./timers.nix
    ./vm.nix
  ];

  users.users.repparw = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = import ./keys.nix;
    shell = pkgs.fish;
    linger = true;
    initialHashedPassword = "$y$j9T$WPuWlgd7OQOePD8XKqNVv0$Pe9XhFT2hKh1YnyDVHxEwOe.IYTMr8K4JUtxBVjEza/";
    description = "repparw";
    extraGroups = [
      "adbusers"
      "wheel"
    ];
  };

  users.users.root.openssh.authorizedKeys.keys =
    config.users.users.repparw.openssh.authorizedKeys.keys;
  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 10;
    };
    efi.canTouchEfiVariables = true;
  };

  image.modules.iso-installer = {
    networking.wireless.enable = false;
  };

  systemd.network = {
    enable = true; # TODO issues with wifi, wait-online
    wait-online.enable = false;
    links."40-eth0" = {
      matchConfig.OriginalName = "eth0";
      linkConfig.WakeOnLan = "magic";
    };
    networks = {
      "10-eth" = {
        matchConfig.Name = "eth0";
        address = [ "192.168.0.18/24" ];
        routes = [ { Gateway = "192.168.0.1"; } ];
        dns = [
          "1.1.1.1"
          "1.0.0.1"
        ];
        linkConfig = {
          RequiredForOnline = "routable";
        };
      };
      "20-wifi" = {
        matchConfig.Name = "wlan0";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "yes";
          Domains = "~."; # prevents dns leakage/conflicts
        };
        dhcpV4Config.RouteMetric = 3000; # significantly higher than ethernet
      };

    };
  };

  networking = {
    wireless.iwd = {
      enable = true;
      settings = {
        General.AddressRandomization = "network";
        Settings.AutoConnect = true;
      };
    };
    useNetworkd = true;
    useDHCP = false;
    nftables.enable = true;
    usePredictableInterfaceNames = false;
    firewall = {
      interfaces.eth0 = {
        allowedTCPPorts = [
          80
          443
        ];
        allowedUDPPorts = [
          54535
        ];
      };
    };
    nameservers = [
      "1.1.1.1#cloudflare-dns.com"
      "1.0.0.1#cloudflare-dns.com"
    ];
  };

  services.dbus.implementation = "broker";

  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSSEC = true;
      DNSOverTLS = true;
    };
  };

  i18n.defaultLocale = "en_IE.UTF-8";

  nix = {
    # extraOptions = ''
    #   !include ${config.sops.secrets.accessTokens.path}
    # '';

    settings = {
      extra-substituters = [
        "https://cachix.cachix.org"
        "https://devenv.cachix.org"
      ];
      extra-trusted-public-keys = [
        "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ];

      use-xdg-base-directories = true;

      trusted-users = [
        "root"
      ];

      allowed-users = [
        "repparw"
      ];

      experimental-features = "nix-command flakes";
    };

    optimise.automatic = true;
  };

  time.timeZone = "America/Argentina/Buenos_Aires";

  environment.systemPackages = [
    inputs.sops-nix.packages.${pkgs.stdenv.hostPlatform.system}.sops-import-keys-hook
  ];

  security = {
    rtkit.enable = true;
    polkit.enable = true;
  };

  hardware.bluetooth.enable = true;
}
