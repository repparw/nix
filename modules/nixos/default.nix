{
  pkgs,
  inputs,
  lib,
  config,
  ...
}: {
  imports = [
    ./autoUpgrade.nix
    ./dlsuite
    ./vm.nix
    ./gaming.nix
    ./hyprland.nix
    ./obs.nix
    ./timers.nix
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  nix = {
    nixPath = ["nixpkgs=${inputs.nixpkgs}"];

    #extraOptions = '' !include ${config.age.secrets.accessTokens.path} '';

    settings = {
      trusted-users = [
        "root"
        "repparw"
      ];

      substituters = [
        "https://nix-community.cachix.org"
      ];

      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
      experimental-features = "nix-command flakes";
    };

    optimise.automatic = true;
  };

  time.timeZone = "America/Argentina/Buenos_Aires";

  i18n = {
    defaultLocale = "en_US.UTF-8";

    extraLocaleSettings = {
      LC_ADDRESS = "es_AR.UTF-8";
      LC_IDENTIFICATION = "es_AR.UTF-8";
      LC_MEASUREMENT = "es_AR.UTF-8";
      LC_MONETARY = "es_AR.UTF-8";
      LC_NAME = "es_AR.UTF-8";
      LC_NUMERIC = "es_AR.UTF-8";
      LC_PAPER = "es_AR.UTF-8";
      LC_TELEPHONE = "es_AR.UTF-8";
      LC_TIME = "es_AR.UTF-8";
    };
  };

  # services.printing.enable = true; # CUPS printing

  fonts = {
    packages = with pkgs; [
      fira-code
      nerd-fonts.fira-code
    ];

    fontconfig.defaultFonts = {
      "sansSerif" = ["FiraCode Nerd Font"];
      "serif" = ["FiraCode Nerd Font"];
      "monospace" = ["FiraCode Nerd Font Mono"];
    };
  };

  environment.pathsToLink = ["/share/zsh"];

  environment.systemPackages = with pkgs; [
    inputs.agenix.packages."${system}".default
    vim
    zsh
    wget
  ];

  programs = {
    zsh.enable = true;

    mosh.enable = true;

    ssh.startAgent = true;
  };

  services = {
    earlyoom.enable = true;

    blueman.enable = true;

    keyd = {
      enable = lib.mkIf (config.networking.hostName != "alpha") true;
      keyboards = {
        default.settings = {
          main = {
            capslock = "overload(control, esc)";
          };
        };
      };
    };

    openssh = {
      enable = true;
      ports = [10000];
      settings.PasswordAuthentication = false;
    };

    fail2ban.enable = true;

    pipewire = {
      enable = true;
      pulse.enable = true;

      wireplumber = {
        extraConfig = {
          "11-disable-autoswitch.conf" = {
            "wireplumber.settings" = {
              "bluetooth.autoswitch-to-headset-profile" = false;
            };
          };
          "20-bt.conf" = {
            "monitor.bluez.properties" = {
              #"bluez5.roles" = [ "a2dp_sink" "a2dp_source" "bap_sink" "bap_source" ];
              "bluez5.enable-hw-volume" = false;
            };
          };
        };
      };
    };
  };

  security.rtkit.enable = true;
  security.polkit.enable = true;

  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          experimental = true; # show battery
          Privacy = "device";
          JustWorksRepairing = "always";
          Class = "0x000100";
          FastConnectable = true;
        };
      };
    };
  };

  systemd.services.logid = {
    startLimitIntervalSec = 0;
    after = ["graphical.target"];
    wantedBy = ["graphical.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lib.getExe pkgs.logiops_0_2_3}";
    };
  };

  environment.etc = {
    "logid.cfg" = {
      text = ''
        devices: (
        {
        	name: "MX Vertical Advanced Ergonomic Mouse";
        	smartshift:
        	{
        		on: true;
        		threshold: 30;
        	};
        	hiresscroll:
        	{
        		hires: true;
        		invert: false;
        		target: false;
        	};
        	dpi: 1600;

        	buttons: (
        		{
        			cid: 0xfd;
        			action =
        			{
        				type: "Keypress";
        				keys: ["KEY_LEFTSHIFT", "KEY_LEFTMETA", "KEY_PRINT"];
        			};
        		}
        	);
        }
        );
      '';
    };
  };
}
