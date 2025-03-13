{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:

{

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # Set your time zone.
  time.timeZone = "America/Argentina/Buenos_Aires";

  # Select internationalisation properties.
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

  # Nerdfonts
  fonts = {
    packages = with pkgs.nerd-fonts; [ fira-code ];

    # Set default font
    fontconfig.defaultFonts = {
      "sansSerif" = [ "FiraCode Nerd Font" ];
      "serif" = [ "FiraCode Nerd Font" ];
      "monospace" = [ "FiraCode Nerd Font Mono" ];
    };
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.pathsToLink = [ "/share/zsh" ];

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
      ports = [ 10000 ];
      settings.PasswordAuthentication = false;
    };

    fail2ban.enable = true;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      # If you want to use JACK applications, uncomment this
      #jack.enable = true;

      wireplumber = {
        enable = true;
        configPackages = [
          (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/11-disable-autoswitch.conf" ''
            wireplumber.settings = {
            bluetooth.autoswitch-to-headset-profile = false;
            }
          '')
          (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/20-bt.conf" ''
            monitor.bluez.properties = {
            #bluez5.roles = [ a2dp_sink a2dp_source bap_sink bap_source ]
            bluez5.enable-hw-volume = false
            }
          '')
        ];
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
    after = [ "graphical.target" ];
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.logiops_0_2_3}/bin/logid";
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

  nix.settings.experimental-features = "nix-command flakes";
}
