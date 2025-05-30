{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:
{
  imports = [
    ./autoUpgrade.nix
    ./gaming.nix
    ./hyprland.nix
    ./obs.nix
    ./services
    ./style.nix
    ./timers.nix
    ./vm.nix
  ];

  users.users.repparw = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF3x0wWO/hQmfN3U8x0OxVqKJ7/nQDWcfg3GkyYKKOkf u0_a452@localhost #termux"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6UbXeSlW/2jkIU9mQIN5xWElnFbA9tw0BfT072WXgR t440"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH ubritos@gmail.com #alpha"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDWoVcpGRe7JDzWKFEYlYlHdm3es5vsRS0TjXF7uWkvVqU+ZCJhL5K8uQfPnpooht2uOmVo++b2I3w8Ue/v9J7EQ7JTcS0qEq/V9cgV9T+D/6pEwV60V1JHuBeJcVNv5raTk7OH3T5ZIX4IXpcptBGKqH2BOnYTw4I0uSS0JDBs6K/272DsECjq9qNJgQ5avsTvBIaFbrsXi2dIbG9TTgblLZM0PSG4dfQOYspdgWHg6YAJVs3AXnaK+ZrQGD+QH/uGW41muy11MHXBIPqRtLb0cruSGr6dOLLykMu5s6iqg4Xs41igd/j2k3R+X6TI6prNLiioWGzD0ROVbGzxrmnL+SBKFtgO9hj8gkeLOYC4IfSFmjU6tvKho5W4gHNtCb+dK9jL+jo8REJ9LBXzPB4rIb4IlbgvMGDs89HCNkXH7GXyMxprDd0lNGlwcMP/qE7ReUVjqSCHoiIXtZgFzm8Z8rG2oFwucVn7jYypWERrTHao/Me795IouwuY6hKby1U= deck@steamdeck # change to ed25519?"
    ];
    shell = pkgs.fish;
    linger = true;
    initialHashedPassword = "$y$j9T$WPuWlgd7OQOePD8XKqNVv0$Pe9XhFT2hKh1YnyDVHxEwOe.IYTMr8K4JUtxBVjEza/";
    description = "repparw";
    extraGroups = [
      "adbusers"
      "wheel"
    ];
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  image.modules.iso-installer = {
    networking.wireless.enable = false;
  };

  networking = {
    networkmanager.enable = true;

    firewall.trustedInterfaces = [
      "enp0s25"
      "enp42s0"
      "wlp3s0"
    ];
  };

  nix = {
    extraOptions = ''
      !include ${config.age.secrets.accessTokens.path}
    '';

    settings = {
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

  environment = {
    systemPackages = with pkgs; [
      inputs.agenix.packages."${system}".default
      vim
    ];
    etc = {
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
  };

  programs = {
    adb.enable = true;

    localsend.enable = true;

    mosh.enable = true;

    nh = {
      enable = true;
      flake = "/home/repparw/nix";
      clean = {
        enable = true;
        extraArgs = "--keep 3 --keep-since 7d";
      };
    };

    ssh.startAgent = true;

    fish.enable = true;
  };

  services = {
    blueman.enable = true;

    earlyoom.enable = true;

    fail2ban.enable = true;

    gvfs.enable = true;

    tailscale.enable = true;

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

    pipewire = {
      enable = true;
      wireplumber = {
        extraConfig = {
          "disable-autoswitch" = {
            "wireplumber.settings" = {
              "bluetooth.autoswitch-to-headset-profile" = false;
            };
          };
          "disable-hw-volume" = {
            "monitor.bluez.properties" = {
              "bluez5.enable-hw-volume" = false;
            };
          };
        };
      };
    };
  };

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
          experimental = true; # show battery
          Privacy = "device";
          JustWorksRepairing = "always";
          Class = "0x000100";
          FastConnectable = true;
        };
      };
    };

    keyboard.qmk.enable = true;
  };

  systemd.services.logid = {
    startLimitIntervalSec = 0;
    after = [ "graphical.target" ];
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lib.getExe pkgs.logiops_0_2_3}";
    };
  };

  nixpkgs.config.allowUnfree = true;
}
