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

  networking = {
    networkmanager.enable = config.networking.hostName != "pi";

    firewall.trustedInterfaces = [
      "enp0s25"
      "enp42s0"
      "wlp3s0"
    ];
  };

  i18n = {
    defaultLocale = "en_DK.UTF-8"; # en_SE not available in glibc?
    # extraLocales = [ "en_GB.UTF-8/UTF-8" ];
    # extraLocaleSettings = {
    #   LC_TIME = "en_GB.UTF-8";
    # };
  };

  nix = {
    # extraOptions = ''
    #   !include ${config.age.secrets.accessTokens.path}
    # '';

    settings = {
      extra-substituters = [ "https://cachix.cachix.org" ];
      extra-trusted-public-keys = [ "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM=" ];

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

  environment.systemPackages = with pkgs; [
    inputs.agenix.packages."${system}".default
  ];

  security = {
    rtkit.enable = true;
    polkit.enable = true;
  };

  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Privacy = "device";
          JustWorksRepairing = "always";
          Class = "0x000100";
          FastConnectable = true;
        };
      };
    };

    keyboard.qmk.enable = true;
  };

  nixpkgs.config.allowUnfree = true;
}
